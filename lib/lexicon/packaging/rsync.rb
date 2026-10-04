# frozen_string_literal: true

require 'open3'

module Lexicon
  module Packaging
    # Copies files to or from a destination rsync understands: a directory, or host:path over SSH.
    class Rsync
      class TransferError < StandardError; end

      # rsync reports a missing source with this status
      MISSING = 23
      # A publication runs rsync several times per package: they share one SSH connection
      ENVIRONMENT = {
        'RSYNC_RSH' => 'ssh -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=/tmp/lexicon-publish-%C ' \
                       '-o ServerAliveInterval=15 -o ServerAliveCountMax=4'
      }.freeze
      # Seconds without any data before a transfer gives up, instead of hanging on a dead connection
      IO_TIMEOUT = 120

      # @param [Pathname, String] source directory whose content is copied
      # @param [String] destination
      # @param [Array<String>] exclude
      def copy_directory(source, destination, exclude: [])
        excludes = exclude.map { |name| "--exclude=#{name}" }

        run('-a', '--partial', "--timeout=#{IO_TIMEOUT}", '--mkpath', *excludes, "#{source}/", "#{destination}/")
      end

      # @param [Pathname, String] source
      # @param [String] destination
      def copy_file(source, destination)
        run('-a', '--mkpath', source.to_s, destination)
      end

      # @param [String] source
      # @param [Pathname] destination
      # @return [Boolean] false when the source does not exist
      def fetch_file(source, destination)
        _output, error, status = Open3.capture3(ENVIRONMENT, 'rsync', '-a', source, destination.to_s)
        return true if status.success?
        return false if status.exitstatus == MISSING

        raise TransferError.new(error.strip)
      end

      # @param [Pathname, String] source
      # @param [String] destination
      # @return [Array<String>] files whose content differs or that are missing at the destination
      def differences(source, destination)
        run('-a', '--checksum', '--dry-run', '--out-format=%n', "#{source}/", "#{destination}/")
          .lines.map(&:strip).reject { |line| line.empty? || line.end_with?('/') }
      end

      private

        # @return [String] standard output
        def run(*arguments)
          output, error, status = Open3.capture3(ENVIRONMENT, 'rsync', *arguments)
          raise TransferError.new(error.strip.presence || "rsync failed with status #{status.exitstatus}") unless status.success?

          output
        end
    end
  end
end
