FROM node:18.16.0-alpine3.17
COPY . .
CMD ["sh", "docker/deploy.sh"]
