#!/bin/bash

echo "Setting permissions for frontend directories..."

# Create npm directories if they don't exist
mkdir -p ../frontend/.npm
mkdir -p ../frontend/node_modules

# Set ownership
sudo chown -R $(id -u):$(id -g) ../frontend
sudo chown -R $(id -u):$(id -g) ../frontend/.npm
sudo chown -R $(id -u):$(id -g) ../frontend/node_modules

# Set permissions
sudo chmod -R 755 ../frontend
sudo chmod -R 755 ../frontend/.npm
sudo chmod -R 755 ../frontend/node_modules

echo "Permissions fixed!"