require 'fileutils'
require 'json'
require 'sinatra'

# ------------------------------------------------------------------------------
# Server setup
# ------------------------------------------------------------------------------
set :bind, '0.0.0.0'
set :port, 3000

# ------------------------------------------------------------------------------
# Endpoint to validate everything is ok
# ------------------------------------------------------------------------------
get '/health' do
    'ok'
end

# ------------------------------------------------------------------------------
# Receive file path and content
# ------------------------------------------------------------------------------
post '/upload' do
    # parse payload
    payload = JSON.parse(request.body.read)

    # extract path
    path = payload['path']
    path = File.expand_path(path)

    # create path if not exists
    path_dir = File.dirname(path)
    puts "Creating path if necessary: #{path_dir}"
    FileUtils.mkdir_p(path_dir) unless File.directory?(path_dir)

    # get file content and save it
    puts "Writing path: #{path}"
    File.open(path, "w") do |f|
        f.write(payload['content'])
    end

    'ok'
end
