# Interior Pro - the line to the Claude API (2026-09-22)
#
# THE ARCHITECTURE RULE (VRAY_POC_PLAN.md): Claude returns NUMBERS, never
# code. This file only carries a question there and JSON back. Nothing that
# comes back is ever eval'd, and no answer reaches the model before the
# CALLER has validated it.
#
# The key is stored per INSTALLATION (Sketchup.write_default), so it is not
# inside the model file, not in the project folder, and not in git:
#   Sketchup.write_default('InteriorPro', 'claude_api_key', 'sk-ant-...')

require 'json'
require 'net/http'
require 'uri'
require 'openssl'

module InteriorPro
  module ClaudeAPI
    # Kill switch: with this false nothing here ever opens a socket.
    USE_CLAUDE_API = true

    ENDPOINT = 'https://api.anthropic.com/v1/messages'.freeze
    API_VER  = '2023-06-01'.freeze
    MODEL    = 'claude-sonnet-5'.freeze

    class << self
      attr_reader :last_usage, :last_stop, :last_blocks

      def key
        Sketchup.read_default('InteriorPro', 'claude_api_key').to_s
      end

      def key?
        k = key
        k.start_with?('sk-ant-') && k.length > 40
      end

      # text: the question. image_png_b64: an optional page or screenshot.
      # Returns the plain text Claude replied with, or raises.
      def ask(text, image_b64 = nil, model: MODEL, max_tokens: 4096, media: 'png')
        raise 'USE_CLAUDE_API is off' unless USE_CLAUDE_API
        raise 'no API key saved on this machine' unless key?

        content = []
        if image_b64 && !image_b64.to_s.empty?
          mt = media.to_s == 'jpeg' ? 'image/jpeg' : 'image/png'
          content << { 'type' => 'image',
                       'source' => { 'type' => 'base64',
                                     'media_type' => mt,
                                     'data' => image_b64 } }
        end
        content << { 'type' => 'text', 'text' => text.to_s }

        body = { 'model' => model,
                 'max_tokens' => max_tokens,
                 'messages' => [{ 'role' => 'user', 'content' => content }] }

        payload = JSON.generate(body)
        begin
          res = post(payload)
        rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, EOFError => e
          puts "[ClaudeAPI] #{e.class} - trying once more"
          res = post(payload)
        end
        unless res.code.to_i == 200
          raise "HTTP #{res.code}: #{res.body.to_s[0, 400]}"
        end

        j = JSON.parse(res.body)
        @last_usage = j['usage']
        @last_stop = j['stop_reason']
        @last_blocks = (j['content'] || []).map { |c| c['type'] }
        (j['content'] || []).select { |c| c['type'] == 'text' }
                            .map { |c| c['text'] }.join
      end

      # Claude is asked for JSON and nothing else, but a model can still wrap
      # it in prose or a code fence, so the braces are cut out before parsing.
      def ask_json(text, image_b64 = nil, **opts)
        raw = ask(text, image_b64, **opts)
        s = raw.index('{')
        e = raw.rindex('}')
        raise "no JSON in the answer: #{raw.to_s[0, 200]}" unless s && e && e > s
        JSON.parse(raw[s..e])
      end

      # One round trip that only MEASURES: does the key work, does SSL work
      # from inside SketchUp, how long it takes and what it costs. Writes
      # nothing and changes nothing in the model.
      def ping!
        puts "[ClaudeAPI] key saved: #{key? ? 'yes' : 'NO'}"
        t = Time.now
        answer = ask('Answer with exactly one word: pong', nil, max_tokens: 1024)
        puts "[ClaudeAPI] answer: #{answer.strip.inspect}"
        puts "[ClaudeAPI] #{(Time.now - t).round(1)}s stop=#{last_stop} blocks=#{last_blocks.inspect}"
        puts "[ClaudeAPI] tokens: #{last_usage.inspect}"
        true
      rescue StandardError => e
        puts "[ClaudeAPI] FAILED: #{e.class}: #{e.message}"
        false
      end

      private

      def post(json)
        uri = URI(ENDPOINT)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 30
        # A plan with many walls can keep Claude thinking for minutes, and a
        # cut-off here throws the whole answer away. Ten minutes, then give up.
        http.read_timeout = 600
        # SketchUp on Windows does not always hand Ruby a CA bundle, so the
        # store is loaded explicitly instead of turning verification off.
        begin
          store = OpenSSL::X509::Store.new
          store.set_default_paths
          http.cert_store = store
        rescue StandardError
          nil
        end
        req = Net::HTTP::Post.new(uri.request_uri)
        req['x-api-key'] = key
        req['anthropic-version'] = API_VER
        req['content-type'] = 'application/json'
        req.body = json
        http.request(req)
      end
    end
  end
end
