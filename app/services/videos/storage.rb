require "fileutils"

module Videos
  class Storage
    class ConfigurationError < StandardError; end

    def self.build
      ENV.fetch("VIDEO_STORAGE_SERVICE", Rails.env.production? ? "r2" : "local") == "r2" ? R2.new : Local.new
    end

    class Local
      def initialize(root: Rails.root.join("tmp/video_storage"))
        @root = root
      end

      def local? = true

      def put(key, io)
        path = path_for(key)
        FileUtils.mkdir_p(path.dirname)
        IO.copy_stream(io, path)
      end

      def upload_file(key, path, content_type:)
        File.open(path, "rb") { |file| put(key, file) }
      end

      def exist?(key) = path_for(key).file?
      def size(key) = path_for(key).size
      def download(key, destination) = FileUtils.cp(path_for(key), destination)
      def read(key) = File.binread(path_for(key))
      def path_for(key) = @root.join(clean_key(key))

      def delete(key)
        FileUtils.rm_f(path_for(key))
      end

      def delete_prefix(prefix)
        FileUtils.rm_rf(path_for(prefix))
      end

      private

      def clean_key(key)
        value = key.to_s.delete_prefix("/")
        raise ArgumentError, "Invalid storage key" if value.split("/").include?("..")

        value
      end
    end

    class R2
      def initialize
        require "aws-sdk-s3"
        @bucket = fetch_env("R2_BUCKET")
        @client = Aws::S3::Client.new(
          endpoint: fetch_env("R2_ENDPOINT"),
          region: "auto",
          access_key_id: fetch_env("R2_ACCESS_KEY_ID"),
          secret_access_key: fetch_env("R2_SECRET_ACCESS_KEY"),
          force_path_style: true
        )
        @presigner = Aws::S3::Presigner.new(client: @client)
      end

      def local? = false

      def presigned_put(key, content_type:, expires_in: 3600)
        @presigner.presigned_url(:put_object, bucket: @bucket, key:, content_type:, expires_in:)
      end

      def presigned_get(key, expires_in: 60)
        @presigner.presigned_url(:get_object, bucket: @bucket, key:, expires_in:)
      end

      def exist?(key)
        @client.head_object(bucket: @bucket, key:)
        true
      rescue Aws::S3::Errors::NotFound
        false
      end

      def size(key) = @client.head_object(bucket: @bucket, key:).content_length
      def download(key, destination) = @client.get_object(bucket: @bucket, key:, response_target: destination.to_s)

      def upload_file(key, path, content_type:)
        File.open(path, "rb") { |body| @client.put_object(bucket: @bucket, key:, body:, content_type:) }
      end

      def delete(key) = @client.delete_object(bucket: @bucket, key:)

      def delete_prefix(prefix)
        continuation_token = nil
        loop do
          response = @client.list_objects_v2(bucket: @bucket, prefix:, continuation_token:)
          response.contents.each_slice(1000) do |objects|
            @client.delete_objects(
              bucket: @bucket,
              delete: { objects: objects.map { |object| { key: object.key } }, quiet: true }
            )
          end
          break unless response.is_truncated

          continuation_token = response.next_continuation_token
        end
      end

      private

      def fetch_env(name)
        ENV[name].presence || raise(ConfigurationError, "#{name} is required for R2 video storage")
      end
    end
  end
end
