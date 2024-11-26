#!/bin/bash

echo "Cleaning up Docker resources..."

# Stop all containers
docker compose down

# Remove all volumes
docker volume rm $(docker volume ls -q)

# Clean npm cache
rm -rf ../frontend/node_modules
rm -rf ../frontend/.npm
rm -rf ../frontend/build

# Clean backend cache
find ../backend -type d -name "__pycache__" -exec rm -rf {} +

echo "Cleanup complete!"
