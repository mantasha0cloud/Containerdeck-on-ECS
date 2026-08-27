#!/bin/bash
# Docker image smoke test - runs the freshly built image and checks /health
set -e

IMAGE_NAME=$1

if [ -z "$IMAGE_NAME" ]; then
  echo "Usage: docker-test.sh <image_name>"
  exit 1
fi

echo "Starting container from image: $IMAGE_NAME"
CONTAINER_ID=$(docker run -d -p 8080:80 "$IMAGE_NAME")

echo "Waiting for container to become healthy..."
sleep 5

STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health)

echo "Stopping and removing test container..."
docker stop "$CONTAINER_ID" > /dev/null
docker rm "$CONTAINER_ID" > /dev/null

if [ "$STATUS" -eq 200 ]; then
  echo "Docker image test PASSED - /health returned $STATUS"
  exit 0
else
  echo "Docker image test FAILED - /health returned $STATUS"
  exit 1
fi
