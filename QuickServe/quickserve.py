import http.server
import socketserver
import argparse
import os

# Define the handler to serve files
Handler = http.server.SimpleHTTPRequestHandler

# Set up the argument parser
parser = argparse.ArgumentParser(description='QuickServe: a quick and easy HTTP server for file sharing.')
parser.add_argument('--port', '-p', type=int, default=8000, help='Port for the HTTP server to listen on (default: 8000)')
parser.add_argument('--directory', '-d', default='.', help='Directory to serve (default: current directory)')

# Parse the command line arguments
args = parser.parse_args()

# Change the directory if provided
if args.directory:
    print(f"Serving files from the directory: {args.directory}")
    os.chdir(args.directory)

# Create the server
with socketserver.TCPServer(("", args.port), Handler) as httpd:
    print(f"QuickServe is running at http://localhost:{args.port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("QuickServe has been stopped.")
        httpd.server_close()