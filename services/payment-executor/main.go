package main

import (
	"context"
	"crypto/rand"
	"encoding/csv"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	pb "github.com/example/payment-executor/gen/executorv1"
)

const (
	tokenTTL    = 60 * time.Second
	lookupDelay = 800 * time.Millisecond
)

var stateNames = map[string]pb.ExecutionState{
	"PENDING": pb.ExecutionState_EXECUTION_STATE_PENDING,
	"SENT":    pb.ExecutionState_EXECUTION_STATE_SENT,
	"SETTLED": pb.ExecutionState_EXECUTION_STATE_SETTLED,
	"FAILED":  pb.ExecutionState_EXECUTION_STATE_FAILED,
}

type store struct {
	mu          sync.RWMutex
	byPayment   map[string]*pb.Execution
	byEndToEnd  map[string]*pb.Execution
	byIdemKey   map[string]*pb.Execution
	tokens      map[string]time.Time
	nextOrdinal int
}

func newStore(path string) (*store, error) {
	fh, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer fh.Close()

	reader := csv.NewReader(fh)
	if _, err := reader.Read(); err != nil {
		return nil, err
	}

	s := &store{
		byPayment:  map[string]*pb.Execution{},
		byEndToEnd: map[string]*pb.Execution{},
		byIdemKey:  map[string]*pb.Execution{},
		tokens:     map[string]time.Time{},
	}

	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		amount, err := strconv.ParseInt(row[3], 10, 64)
		if err != nil {
			return nil, err
		}
		ex := &pb.Execution{
			PaymentId:   row[0],
			EndToEndId:  row[1],
			ProgramId:   row[2],
			AmountMinor: amount,
			State:       stateNames[row[4]],
			SubmittedAt: row[5],
			SettledAt:   row[6],
		}
		s.byPayment[ex.PaymentId] = ex
		s.byEndToEnd[ex.EndToEndId] = ex
		s.nextOrdinal++
	}
	return s, nil
}

func (s *store) issue() (string, int32) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	tok := hex.EncodeToString(buf)
	s.mu.Lock()
	s.tokens[tok] = time.Now().Add(tokenTTL)
	for existing, expiry := range s.tokens {
		if time.Now().After(expiry.Add(5 * time.Minute)) {
			delete(s.tokens, existing)
		}
	}
	s.mu.Unlock()
	return tok, int32(tokenTTL.Seconds())
}

func (s *store) valid(tok string) bool {
	s.mu.RLock()
	expiry, ok := s.tokens[tok]
	s.mu.RUnlock()
	return ok && time.Now().Before(expiry)
}

type tokenServer struct {
	pb.UnimplementedTokenServiceServer
	s      *store
	id     string
	secret string
}

func (t *tokenServer) IssueToken(ctx context.Context, req *pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
	if req.GetClientId() != t.id || req.GetClientSecret() != t.secret {
		return nil, status.Error(codes.PermissionDenied, "client_id or client_secret rejected")
	}
	tok, ttl := t.s.issue()
	return &pb.IssueTokenResponse{Token: tok, ExpiresInSeconds: ttl}, nil
}

type executionServer struct {
	pb.UnimplementedExecutionServiceServer
	s *store
}

func (e *executionServer) LookupByEndToEndId(ctx context.Context, req *pb.LookupByEndToEndIdRequest) (*pb.Execution, error) {
	select {
	case <-time.After(lookupDelay):
	case <-ctx.Done():
		return nil, status.Error(codes.Canceled, "caller went away")
	}
	e.s.mu.RLock()
	found, ok := e.s.byEndToEnd[req.GetEndToEndId()]
	e.s.mu.RUnlock()
	if !ok {
		return nil, status.Errorf(codes.NotFound, "no execution for end_to_end_id %s", req.GetEndToEndId())
	}
	return found, nil
}

func (e *executionServer) GetExecution(ctx context.Context, req *pb.GetExecutionRequest) (*pb.Execution, error) {
	e.s.mu.RLock()
	found, ok := e.s.byPayment[req.GetPaymentId()]
	e.s.mu.RUnlock()
	if !ok {
		return nil, status.Errorf(codes.NotFound, "no execution %s", req.GetPaymentId())
	}
	return found, nil
}

func (e *executionServer) SubmitPayment(ctx context.Context, req *pb.SubmitPaymentRequest) (*pb.Execution, error) {
	if req.GetIdempotencyKey() == "" {
		return nil, status.Error(codes.InvalidArgument, "idempotency_key is required")
	}
	if req.GetEndToEndId() == "" || req.GetProgramId() == "" {
		return nil, status.Error(codes.InvalidArgument, "end_to_end_id and program_id are required")
	}
	if req.GetAmountMinor() <= 0 {
		return nil, status.Error(codes.InvalidArgument, "amount_minor must be positive")
	}

	e.s.mu.Lock()
	defer e.s.mu.Unlock()

	if prior, ok := e.s.byIdemKey[req.GetIdempotencyKey()]; ok {
		if prior.EndToEndId != req.GetEndToEndId() || prior.AmountMinor != req.GetAmountMinor() {
			return nil, status.Error(codes.AlreadyExists, "idempotency_key already used with different arguments")
		}
		return prior, nil
	}

	if existing, ok := e.s.byEndToEnd[req.GetEndToEndId()]; ok {
		return nil, status.Errorf(codes.AlreadyExists, "end_to_end_id %s already executed as %s", req.GetEndToEndId(), existing.PaymentId)
	}

	e.s.nextOrdinal++
	ex := &pb.Execution{
		PaymentId:   fmt.Sprintf("PAY-9%07X", e.s.nextOrdinal),
		EndToEndId:  req.GetEndToEndId(),
		ProgramId:   req.GetProgramId(),
		AmountMinor: req.GetAmountMinor(),
		State:       pb.ExecutionState_EXECUTION_STATE_PENDING,
		SubmittedAt: time.Now().UTC().Format("2006-01-02"),
	}
	e.s.byPayment[ex.PaymentId] = ex
	e.s.byEndToEnd[ex.EndToEndId] = ex
	e.s.byIdemKey[req.GetIdempotencyKey()] = ex
	return ex, nil
}

func authInterceptor(s *store) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if strings.HasPrefix(info.FullMethod, "/executor.v1.TokenService/") ||
			strings.HasPrefix(info.FullMethod, "/grpc.health.v1.Health/") ||
			strings.HasPrefix(info.FullMethod, "/grpc.reflection.") {
			return handler(ctx, req)
		}
		md, ok := metadata.FromIncomingContext(ctx)
		if !ok {
			return nil, status.Error(codes.Unauthenticated, "missing metadata")
		}
		values := md.Get("authorization")
		if len(values) == 0 {
			return nil, status.Error(codes.Unauthenticated, "missing authorization metadata")
		}
		tok := strings.TrimPrefix(values[0], "Bearer ")
		if tok == values[0] {
			return nil, status.Error(codes.Unauthenticated, "authorization must be 'Bearer <token>'")
		}
		if !s.valid(tok) {
			return nil, status.Error(codes.Unauthenticated, "token missing or expired")
		}
		return handler(ctx, req)
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8083"
	}
	clientID := os.Getenv("CLIENT_ID")
	if clientID == "" {
		clientID = "orchestrator"
	}
	clientSecret := os.Getenv("CLIENT_SECRET")
	if clientSecret == "" {
		clientSecret = "ex_secret_4d9b1c7a"
	}

	st, err := newStore("data/executions.csv")
	if err != nil {
		log.Fatal(err)
	}

	healthPort := os.Getenv("HEALTH_PORT")
	if healthPort == "" {
		healthPort = "8093"
	}
	go func() {
		mux := http.NewServeMux()
		mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("content-type", "application/json")
			_, _ = io.WriteString(w, `{"state":"up","grpc_port":`+port+`}`+"\n")
		})
		if err := http.ListenAndServe(":"+healthPort, mux); err != nil {
			log.Print(err)
		}
	}()

	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatal(err)
	}

	srv := grpc.NewServer(grpc.UnaryInterceptor(authInterceptor(st)))
	pb.RegisterTokenServiceServer(srv, &tokenServer{s: st, id: clientID, secret: clientSecret})
	pb.RegisterExecutionServiceServer(srv, &executionServer{s: st})
	healthpb.RegisterHealthServer(srv, health.NewServer())
	reflection.Register(srv)

	if err := srv.Serve(lis); err != nil {
		log.Fatal(err)
	}
}
