# Use an official lightweight Alpine image with bash installed as a parent image
FROM alpine:3.7

# Install any needed packages specified in requirements.txt
RUN apk add --no-cache bash curl sudo

# Set the working directory in the container to /app
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . /app

# Make the script executable
RUN chmod +x /app/install.sh

# Run the command to start the application
CMD ["/app/install.sh"]
