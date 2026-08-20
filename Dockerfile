FROM node:24-bookworm-slim AS dependencies

WORKDIR /app
COPY package.json package-lock.json ./
COPY apps ./apps
COPY packages ./packages
COPY tsconfig.base.json ./
RUN npm ci

FROM dependencies AS web-build
ARG EXPO_PUBLIC_API_URL
ENV EXPO_PUBLIC_API_URL=$EXPO_PUBLIC_API_URL
RUN npm run export:web --workspace=@form/mobile

FROM nginx:1.29-alpine AS web
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=web-build /app/apps/mobile/dist /usr/share/nginx/html

FROM dependencies AS api
CMD ["npm", "run", "start", "--workspace=@form/api"]

FROM dependencies AS worker
CMD ["npm", "run", "start", "--workspace=@form/worker"]
