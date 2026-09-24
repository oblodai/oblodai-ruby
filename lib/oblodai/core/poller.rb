# frozen_string_literal: true

require_relative "util"
require_relative "../errors"

module Oblodai
  # A long-running operation (a batch, a document job): its {#id}, the create call's answer
  # {#result}, and {#wait}, which polls until the status is terminal for that operation (the
  # contract's `x-sdk-poll`, generated into {Oblodai::Generated::LRO}) and returns the last poll
  # answer. A terminal status is returned, not raised, so a `failed` job is inspected like a
  # finished one.
  #
  #     job = client.batches.create_payout(items: [...])
  #     info = job.wait(timeout: 600)
  #     puts info.status
  class Job
    # @return [String] the job's id (`batch_id`, `job_id`)
    attr_reader :id
    # @return [Object] the create call's answer, parsed as the method would return it
    attr_reader :result

    # @param id [String]
    # @param result [Object]
    # @param poll [#call] one poll: returns the parsed poll answer
    # @param download [#call, nil] the finished job's file, for jobs that make one
    # @param terminal [Array<String>] statuses after which the job no longer changes
    # @param status_field [String] the poll answer's status field
    def initialize(id:, result:, poll:, terminal:, download: nil, status_field: "status")
      @id = id
      @result = result
      @poll = poll
      @download = download
      @terminal = terminal
      @status_field = status_field
    end

    # Poll every `interval` seconds until the job's status is terminal; return that answer.
    # @param timeout [Numeric] seconds to wait at most
    # @param interval [Numeric] seconds between polls
    # @return [Object] the last poll answer
    # @raise [Oblodai::TransportError] `transport.deadline` when `timeout` passes first
    def wait(timeout: 300, interval: 2)
      deadline = Util.monotonic_ms + (timeout * 1000.0)
      loop do
        answer = @poll.call
        status = Job.status_of(answer, @status_field)
        return answer if @terminal.include?(status)

        remaining = (deadline - Util.monotonic_ms) / 1000.0
        unless remaining.positive?
          raise TransportError.new("transport.deadline",
                                   "job #{@id} is still #{status.empty? ? "unfinished" : status} after #{timeout}s")
        end

        pause([interval, remaining].min)
      end
    end

    # The finished job's file (document jobs only).
    # @return [Oblodai::FileResult]
    def download
      raise ArgumentError, "job #{@id} produces no file to download" if @download.nil?

      @download.call
    end

    def inspect
      "#<Oblodai::Job id=#{@id.inspect}>"
    end

    # The status (`field`) of a poll answer, model or Hash.
    # @return [String]
    def self.status_of(answer, field = "status")
      status = if answer.is_a?(Hash)
                 answer[field] || answer[field.to_sym]
               elsif answer.respond_to?(field)
                 answer.public_send(field)
               end
      status.to_s
    end

    private

    def pause(seconds)
      sleep(seconds)
    end
  end
end
