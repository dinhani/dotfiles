require "fileutils"
require "json"
require "sinatra"

set :bind, "0.0.0.0"
set :port, 3000

get "/health" do
    "ok"
end

# Receive file path and content
post "/upload" do
    # parse input
    payload = parse_payload(request)
    path = parse_path(payload)

    # create path dir if not exists
    path_dir = File.dirname(path)
    FileUtils.mkdir_p(path_dir) unless File.directory?(path_dir)

    # write file content
    puts "Writing: #{path}"
    File.open(path, "w") do |f|
        f.write(payload["content"])
    end

    "ok"
end

post "/download" do
    # parse input
    payload = parse_payload(request)
    path = parse_path(payload)

    # read file content
    puts "Reading: #{path}"
    File.open(path, "r").read
end

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

private def parse_payload(request)
    JSON.parse(request.body.read)
end

private def parse_path(payload)
    path = payload["path"]
    File.expand_path(path)
end