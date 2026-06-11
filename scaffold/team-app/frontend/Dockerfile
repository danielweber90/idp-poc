FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
# TEAM_NAME must match teamName in deploy/values.yaml — baked into the static bundle
ARG TEAM_NAME=my-team
ENV VITE_BASE_PATH=/${TEAM_NAME}/
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
