require "uri"
require "net/http"
require "fileutils"
require "json"
require "docker"
require_relative "path_helper"

class BuildpackRunner
  include PathHelper

  HOST_PORT      = "3000"
  HOST_IP        = "127.0.0.1"
  CONTAINER_PORT = "3000"

  def initialize(fixture, debug = false)
    @debug     = debug
    @image     = build_image(fixture)
    puts @image.id if @debug
    @container = Docker::Container.create(
      'Image'      => @image.id,
      'HostConfig' => {
        'PortBindings' => {
          "#{CONTAINER_PORT}/tcp" => [{
            "HostIp" => HOST_IP,
            "HostPort": HOST_PORT, 
          }]
        }
      }
    )
  end

  def run
    #@container.tap(&:start).attach { |stream, chunk| puts "#{stream}: #{chunk}" }
    @container.start
    sleep(1)
    yield(@container)
    @container.stop
  end

  def get(path)
    response = nil
    run do
      uri      = URI("http://#{HOST_IP}:#{HOST_PORT}/#{path}")
      response = Net::HTTP.get_response(uri)
    end

    return response
  end

  def destroy
    unless @debug
      @container.delete(force: true)
      @image.remove(force: true)
    end
  end

  private
  def build_image(fixture)
    image = nil

    Dir.mktmpdir do |tmpdir|
      fixture_path = fixtures_path(fixture)
      dest_bp_dir  = Pathname.new(File.join(tmpdir, "buildpack"))
      print_output =
        if @debug
          -> (chunk) {
            json = JSON.parse(chunk)
            puts json["stream"]
          }
        else
          -> (chunk) { nil }
        end

      FileUtils.mkdir_p(dest_bp_dir)
      FileUtils.cp_r(buildpack_path("bin"), dest_bp_dir)
      FileUtils.cp_r(buildpack_path("scripts"), dest_bp_dir)
      FileUtils.cp_r(Dir.glob(fixture_path + "*"), tmpdir)
      image = Docker::Image.build_from_dir(tmpdir, &print_output)
    end

    image
  end
end
