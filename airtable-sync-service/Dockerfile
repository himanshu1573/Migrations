FROM node:18-slim

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

# Create an empty sync state if it doesn't exist
RUN echo '{"last_sync": null}' > sync_state.json

CMD ["npm", "start"]
