require "fileutils"
require "chef/cookbook/metadata"
require "mixlib/shellout"

module Drone
  class Chef
    #
    # Class for uploading cookbooks to a Chef Server
    #
    class Processor
      attr_accessor :config

      #
      # Initialize an instance
      #
      def initialize(config)
        self.config = config

        yield(
          self
        ) if block_given?
      end

      #
      # Validate that all requirements are met
      #
      def validate!
        raise "Please provide an organization" if config.org.nil?
      end

      #
      # Write required config files
      #
      def configure!
        config.configure!

        write_knife_rb
        write_berks_config
      end

      #
      # Upload the cookbook to a Chef Server
      #
      def upload!
        berks_install if berksfile?
        berks_upload if berksfile?
        knife_upload unless cookbook? || !chef_data?
      end

      protected

      #
      # Are we uploading a cookbook?
      #
      def cookbook?
        File.exist? "#{@config.workspace.path}/metadata.rb"
      end

      #
      # Is there a Berksfile?
      #
      def berksfile?
        return true if File.exist? "#{@config.workspace}/Berksfile"
        return true if File.exist? "#{@config.workspace}/Berksfile.lock"
        false
      end

      def url
        "#{@config.server}/organizations/#{@config.vargs["org"]}"
      end

      def write_knife_rb
        config.knife_config_path.open "w" do |f|
          f.puts "node_name '#{@config.user}'"
          f.puts "client_key '#{@config.keyfile_path}'"
          f.puts "chef_server_url '#{url}'"
          f.puts "chef_repo_path '#{@config.workspace.path}'"
          f.puts "ssl_verify_mode #{@config.ssl_mode}"
        end
      end

      def write_berks_config
        return if config.ssl_verify?
        config.berks_config_path.open "w" do |f|
          # config.ssl_verify?
          f.puts '{"ssl":{"verify":false}}'
        end
      end

      #
      # Command to gather necessary cookbooks
      #
      def berks_install
        logger.info "Retrieving cookbooks"
        cmd = Mixlib::ShellOut
              .new("berks install -b #{@config.workspace.path}/Berksfile")
        cmd.run_command

        raise "ERROR: Failed to retrieve cookbooks" if cmd.error?
      end

      #
      # Command to upload cookbook(s) with Berkshelf
      #
      def berks_upload # rubocop:disable AbcSize
        logger.info "Running berks upload"
        command = ["berks upload"]
        command << cookbook.name unless config.recursive?
        command << "-b #{@config.workspace.path}/Berksfile"
        command << "--no-freeze" unless config.freeze?
        cmd = Mixlib::ShellOut.new(command.join(" "))
        cmd.run_command

        logger.debug "berks upload stdout: #{cmd.stdout}"
        raise "ERROR: Failed to upload cookbook" if cmd.error?
      end

      def chef_data?
        !Dir.glob("#{@config.workspace.path}/{roles,environments,data_bags}")
            .empty?
      end

      #
      # Upload any roles, environments and data_bags
      #
      def knife_upload # rubocop:disable AbcSize
        logger.info "Uploading roles, environments and data bags"
        command = ["knife upload"]
        command << "."
        command << "-c #{@config.knife_config_path}"

        Dir.chdir(@config.workspace.path)

        cmd = Mixlib::ShellOut.new(command.join(" "))
        cmd.run_command

        logger.debug "knife upload stdout: #{cmd.stdout}"
        raise "ERROR: knife upload failed" if cmd.error?
      end

      def cookbook
        @metadata ||= begin
          metadata = ::Chef::Cookbook::Metadata.new
          metadata.from_file("#{@config.workspace.path}/metadata.rb")
          metadata
        end
      end

      def logger
        config.logger
      end
    end
  end
end
