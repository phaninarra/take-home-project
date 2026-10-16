#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>
#include <regex.h>
#include <microhttpd.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <openssl/hmac.h>
#include <openssl/sha.h>
#include <openssl/evp.h>

#define MAX_INSTRUCTIONS 4096
#define MAX_BODY 65536
#define MAX_SKEW 300
#define AMOUNT_CEILING 5000000LL

typedef struct {
    char end_to_end_id[32];
    char payee_id[16];
    char program_id[16];
    long long amount_minor;
    char currency[8];
    char requested_date[16];
    char status[16];
} instruction_t;

static instruction_t registry[MAX_INSTRUCTIONS];
static int registry_count = 0;

static const char *key_id = "ir_key_01";
static const char *shared_secret = "ir_secret_b82f1e6d";

typedef struct {
    char *data;
    size_t len;
} body_buffer_t;

static void copy_field(char *dest, size_t cap, xmlNodePtr node) {
    xmlChar *value = xmlNodeGetContent(node);
    if (value) {
        snprintf(dest, cap, "%s", (const char *)value);
        xmlFree(value);
    }
}

static void load_registry(const char *path) {
    xmlDocPtr doc = xmlReadFile(path, NULL, XML_PARSE_NOBLANKS);
    if (!doc) {
        fprintf(stderr, "cannot read %s\n", path);
        exit(1);
    }
    xmlNodePtr root = xmlDocGetRootElement(doc);
    for (xmlNodePtr n = root->children; n && registry_count < MAX_INSTRUCTIONS; n = n->next) {
        if (n->type != XML_ELEMENT_NODE) {
            continue;
        }
        instruction_t *slot = &registry[registry_count];
        memset(slot, 0, sizeof(*slot));
        snprintf(slot->currency, sizeof(slot->currency), "USD");
        for (xmlNodePtr f = n->children; f; f = f->next) {
            if (f->type != XML_ELEMENT_NODE) {
                continue;
            }
            const char *name = (const char *)f->name;
            if (strcmp(name, "EndToEndId") == 0) {
                copy_field(slot->end_to_end_id, sizeof(slot->end_to_end_id), f);
            } else if (strcmp(name, "PayeeId") == 0) {
                copy_field(slot->payee_id, sizeof(slot->payee_id), f);
            } else if (strcmp(name, "ProgramId") == 0) {
                copy_field(slot->program_id, sizeof(slot->program_id), f);
            } else if (strcmp(name, "RequestedDate") == 0) {
                copy_field(slot->requested_date, sizeof(slot->requested_date), f);
            } else if (strcmp(name, "Status") == 0) {
                copy_field(slot->status, sizeof(slot->status), f);
            } else if (strcmp(name, "Amount") == 0) {
                char raw[32] = {0};
                copy_field(raw, sizeof(raw), f);
                slot->amount_minor = atoll(raw);
                xmlChar *ccy = xmlGetProp(f, (const xmlChar *)"Ccy");
                if (ccy) {
                    snprintf(slot->currency, sizeof(slot->currency), "%s", (const char *)ccy);
                    xmlFree(ccy);
                }
            }
        }
        registry_count++;
    }
    xmlFreeDoc(doc);
}

static instruction_t *find_instruction(const char *end_to_end_id) {
    for (int i = 0; i < registry_count; i++) {
        if (strcmp(registry[i].end_to_end_id, end_to_end_id) == 0) {
            return &registry[i];
        }
    }
    return NULL;
}

static void sha256_hex(const char *input, size_t len, char *out) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256((const unsigned char *)input, len, digest);
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        sprintf(out + (i * 2), "%02x", digest[i]);
    }
    out[SHA256_DIGEST_LENGTH * 2] = '\0';
}

static void hmac_base64(const char *message, char *out, size_t cap) {
    unsigned char mac[EVP_MAX_MD_SIZE];
    unsigned int mac_len = 0;
    HMAC(EVP_sha256(), shared_secret, (int)strlen(shared_secret),
         (const unsigned char *)message, strlen(message), mac, &mac_len);
    unsigned char encoded[128];
    int written = EVP_EncodeBlock(encoded, mac, (int)mac_len);
    if (written < 0) {
        out[0] = '\0';
        return;
    }
    snprintf(out, cap, "%s", (const char *)encoded);
}

static int authorised(struct MHD_Connection *connection, const char *method,
                      const char *url, const char *body, size_t body_len,
                      const char **reason) {
    const char *supplied_key = MHD_lookup_connection_value(connection, MHD_HEADER_KIND, "X-Key-Id");
    const char *timestamp = MHD_lookup_connection_value(connection, MHD_HEADER_KIND, "X-Timestamp");
    const char *authorization = MHD_lookup_connection_value(connection, MHD_HEADER_KIND, "Authorization");

    if (!supplied_key || !timestamp || !authorization) {
        *reason = "X-Key-Id, X-Timestamp and Authorization are all required";
        return 0;
    }
    if (strcmp(supplied_key, key_id) != 0) {
        *reason = "unknown X-Key-Id";
        return 0;
    }
    if (strncmp(authorization, "HMAC-SHA256 ", 12) != 0) {
        *reason = "Authorization must be 'HMAC-SHA256 <base64 signature>'";
        return 0;
    }

    long supplied_time = atol(timestamp);
    long now = (long)time(NULL);
    long skew = now > supplied_time ? now - supplied_time : supplied_time - now;
    if (skew > MAX_SKEW) {
        *reason = "X-Timestamp is outside the permitted 300 second window";
        return 0;
    }

    char body_hash[(SHA256_DIGEST_LENGTH * 2) + 1];
    sha256_hex(body ? body : "", body ? body_len : 0, body_hash);

    char to_sign[1024];
    snprintf(to_sign, sizeof(to_sign), "%s\n%s\n%s\n%s", method, url, timestamp, body_hash);

    char expected[128];
    hmac_base64(to_sign, expected, sizeof(expected));

    if (strcmp(expected, authorization + 12) != 0) {
        *reason = "signature does not match";
        return 0;
    }
    return 1;
}

static enum MHD_Result respond(struct MHD_Connection *connection, unsigned int code,
                               const char *xml) {
    struct MHD_Response *response = MHD_create_response_from_buffer(
        strlen(xml), (void *)xml, MHD_RESPMEM_MUST_COPY);
    MHD_add_response_header(response, "Content-Type", "application/xml; charset=utf-8");
    enum MHD_Result result = MHD_queue_response(connection, code, response);
    MHD_destroy_response(response);
    return result;
}

static enum MHD_Result respond_fault(struct MHD_Connection *connection, unsigned int code,
                                     const char *fault_code, const char *detail) {
    char xml[1024];
    snprintf(xml, sizeof(xml),
             "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
             "<Fault>\n  <Code>%s</Code>\n  <Detail>%s</Detail>\n</Fault>\n",
             fault_code, detail);
    return respond(connection, code, xml);
}

static enum MHD_Result respond_instruction(struct MHD_Connection *connection,
                                           unsigned int code, const instruction_t *ins) {
    char xml[2048];
    snprintf(xml, sizeof(xml),
             "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
             "<Instruction>\n"
             "  <EndToEndId>%s</EndToEndId>\n"
             "  <PayeeId>%s</PayeeId>\n"
             "  <ProgramId>%s</ProgramId>\n"
             "  <Amount Ccy=\"%s\">%lld</Amount>\n"
             "  <RequestedDate>%s</RequestedDate>\n"
             "  <Status>%s</Status>\n"
             "</Instruction>\n",
             ins->end_to_end_id, ins->payee_id, ins->program_id, ins->currency,
             ins->amount_minor, ins->requested_date, ins->status);
    return respond(connection, code, xml);
}

static int matches(const char *pattern, const char *value) {
    regex_t compiled;
    if (regcomp(&compiled, pattern, REG_EXTENDED | REG_NOSUB) != 0) {
        return 0;
    }
    int outcome = regexec(&compiled, value, 0, NULL, 0);
    regfree(&compiled);
    return outcome == 0;
}

static enum MHD_Result create_instruction(struct MHD_Connection *connection,
                                          const char *body, size_t body_len) {
    xmlDocPtr doc = xmlReadMemory(body, (int)body_len, "request.xml", NULL, XML_PARSE_NOBLANKS);
    if (!doc) {
        return respond_fault(connection, 400, "MALFORMED_XML", "request body is not well formed XML");
    }

    instruction_t candidate;
    memset(&candidate, 0, sizeof(candidate));
    snprintf(candidate.currency, sizeof(candidate.currency), "USD");
    snprintf(candidate.status, sizeof(candidate.status), "VALIDATED");

    xmlNodePtr root = xmlDocGetRootElement(doc);
    if (!root || strcmp((const char *)root->name, "Instruction") != 0) {
        xmlFreeDoc(doc);
        return respond_fault(connection, 400, "MALFORMED_XML", "root element must be Instruction");
    }

    for (xmlNodePtr f = root->children; f; f = f->next) {
        if (f->type != XML_ELEMENT_NODE) {
            continue;
        }
        const char *name = (const char *)f->name;
        if (strcmp(name, "EndToEndId") == 0) {
            copy_field(candidate.end_to_end_id, sizeof(candidate.end_to_end_id), f);
        } else if (strcmp(name, "PayeeId") == 0) {
            copy_field(candidate.payee_id, sizeof(candidate.payee_id), f);
        } else if (strcmp(name, "ProgramId") == 0) {
            copy_field(candidate.program_id, sizeof(candidate.program_id), f);
        } else if (strcmp(name, "RequestedDate") == 0) {
            copy_field(candidate.requested_date, sizeof(candidate.requested_date), f);
        } else if (strcmp(name, "Amount") == 0) {
            char raw[32] = {0};
            copy_field(raw, sizeof(raw), f);
            candidate.amount_minor = atoll(raw);
            xmlChar *ccy = xmlGetProp(f, (const xmlChar *)"Ccy");
            if (ccy) {
                snprintf(candidate.currency, sizeof(candidate.currency), "%s", (const char *)ccy);
                xmlFree(ccy);
            }
        }
    }
    xmlFreeDoc(doc);

    if (!matches("^E2E-[0-9A-F]{8}$", candidate.end_to_end_id)) {
        return respond_fault(connection, 422, "RULE_E2E_FORMAT",
                             "EndToEndId must match E2E- followed by 8 uppercase hex characters");
    }
    if (!matches("^PY-[0-9]{5}$", candidate.payee_id)) {
        return respond_fault(connection, 422, "RULE_PAYEE_FORMAT",
                             "PayeeId must match PY- followed by 5 digits");
    }
    if (!matches("^PRG-[A-Z]+$", candidate.program_id)) {
        return respond_fault(connection, 422, "RULE_PROGRAM_FORMAT",
                             "ProgramId must match PRG- followed by uppercase letters");
    }
    if (strcmp(candidate.currency, "USD") != 0) {
        return respond_fault(connection, 422, "RULE_CURRENCY",
                             "only USD instructions are accepted");
    }
    if (candidate.amount_minor <= 0) {
        return respond_fault(connection, 422, "RULE_AMOUNT_POSITIVE",
                             "Amount must be greater than zero");
    }
    if (candidate.amount_minor > AMOUNT_CEILING) {
        return respond_fault(connection, 422, "RULE_AMOUNT_CEILING",
                             "Amount exceeds the per instruction ceiling of 5000000");
    }
    if (!matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", candidate.requested_date)) {
        return respond_fault(connection, 422, "RULE_DATE_FORMAT",
                             "RequestedDate must be an ISO date, YYYY-MM-DD");
    }
    if (find_instruction(candidate.end_to_end_id)) {
        return respond_fault(connection, 409, "DUPLICATE_END_TO_END_ID",
                             "an instruction with that EndToEndId already exists");
    }
    if (registry_count >= MAX_INSTRUCTIONS) {
        return respond_fault(connection, 507, "REGISTRY_FULL", "registry is at capacity");
    }

    registry[registry_count] = candidate;
    instruction_t *stored = &registry[registry_count];
    registry_count++;
    return respond_instruction(connection, 201, stored);
}

static enum MHD_Result handle(void *cls, struct MHD_Connection *connection,
                              const char *url, const char *method, const char *version,
                              const char *upload_data, size_t *upload_data_size,
                              void **con_cls) {
    (void)cls;
    (void)version;

    if (strcmp(url, "/health") == 0 && strcmp(method, "GET") == 0) {
        return respond(connection, 200,
                       "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Health><State>up</State></Health>\n");
    }

    if (strcmp(method, "POST") == 0) {
        body_buffer_t *buffer = *con_cls;
        if (!buffer) {
            buffer = calloc(1, sizeof(body_buffer_t));
            buffer->data = calloc(1, MAX_BODY + 1);
            *con_cls = buffer;
            return MHD_YES;
        }
        if (*upload_data_size > 0) {
            size_t room = MAX_BODY - buffer->len;
            size_t take = *upload_data_size < room ? *upload_data_size : room;
            memcpy(buffer->data + buffer->len, upload_data, take);
            buffer->len += take;
            *upload_data_size = 0;
            return MHD_YES;
        }

        const char *reason = NULL;
        if (!authorised(connection, method, url, buffer->data, buffer->len, &reason)) {
            return respond_fault(connection, 401, "UNAUTHORISED", reason);
        }
        if (strcmp(url, "/instructions") != 0) {
            return respond_fault(connection, 404, "NO_ROUTE", "nothing accepts POST at that path");
        }
        return create_instruction(connection, buffer->data, buffer->len);
    }

    if (strcmp(method, "GET") != 0) {
        return respond_fault(connection, 405, "METHOD_NOT_ALLOWED", "only GET and POST are supported");
    }

    const char *reason = NULL;
    if (!authorised(connection, method, url, "", 0, &reason)) {
        return respond_fault(connection, 401, "UNAUTHORISED", reason);
    }

    if (strncmp(url, "/instructions/", 14) == 0) {
        instruction_t *found = find_instruction(url + 14);
        if (!found) {
            return respond_fault(connection, 404, "NOT_FOUND", "no instruction with that EndToEndId");
        }
        return respond_instruction(connection, 200, found);
    }

    return respond_fault(connection, 404, "NO_ROUTE", "nothing at that path");
}

static void cleanup(void *cls, struct MHD_Connection *connection, void **con_cls,
                    enum MHD_RequestTerminationCode code) {
    (void)cls;
    (void)connection;
    (void)code;
    body_buffer_t *buffer = *con_cls;
    if (buffer) {
        free(buffer->data);
        free(buffer);
        *con_cls = NULL;
    }
}

int main(void) {
    const char *port_env = getenv("PORT");
    unsigned short port = port_env ? (unsigned short)atoi(port_env) : 8082;
    const char *key_env = getenv("KEY_ID");
    const char *secret_env = getenv("SHARED_SECRET");
    if (key_env) {
        key_id = key_env;
    }
    if (secret_env) {
        shared_secret = secret_env;
    }

    LIBXML_TEST_VERSION
    load_registry("data/instructions.xml");
    fprintf(stderr, "loaded %d instructions\n", registry_count);

    struct MHD_Daemon *daemon = MHD_start_daemon(
        MHD_USE_INTERNAL_POLLING_THREAD, port, NULL, NULL,
        &handle, NULL,
        MHD_OPTION_NOTIFY_COMPLETED, &cleanup, NULL,
        MHD_OPTION_CONNECTION_TIMEOUT, (unsigned int)30,
        MHD_OPTION_END);

    if (!daemon) {
        fprintf(stderr, "cannot bind port %u\n", port);
        return 1;
    }

    pause();
    MHD_stop_daemon(daemon);
    xmlCleanupParser();
    return 0;
}
