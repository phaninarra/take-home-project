FROM node:22-alpine
WORKDIR /app
COPY server.js ./
COPY data ./data
ENV PORT=8081
EXPOSE 8081
CMD ["node", "server.js"]
