ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-alpine AS build
ENV NG_CLI_ANALYTICS=false
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npx ng build --configuration production \
 && mkdir /out \
 && if ls -d dist/*/browser >/dev/null 2>&1; then cp -r dist/*/browser/. /out/; else cp -r dist/*/. /out/; fi

FROM nginx:1.27-alpine
COPY --from=config nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /out /usr/share/nginx/html
