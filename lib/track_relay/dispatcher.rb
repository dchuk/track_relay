# frozen_string_literal: true

require "active_support/notifications"

module TrackRelay
  # Single ActiveSupport::Notifications subscription that fans
  # `track_relay.event` notifications out to every subscriber in
  # {Configuration#subscribers}.
  #
  # **Error contract — collect-then-reraise (locked in 01-CONTEXT.md):**
  #
  # 1. Iterate every configured subscriber, calling `handle(payload)`.
  # 2. {Subscribers::Base#handle} returns `nil` on success or the
  #    StandardError on a sync failure (it never re-raises inline). For
  #    non-Base subscribers that ignore the contract and raise inline,
  #    a defensive rescue here preserves the "peers still run"
  #    invariant — exceptions from those rogues are also collected.
  # 3. AFTER fan-out completes, if
  #    {Configuration#swallow_subscriber_errors} is `false` AND any
  #    exception was collected, re-raise the **first** one. This is
  #    the locked dev/test loudness rule: surface failures, but only
  #    after every peer has had its chance to receive the event.
  #
  # **Lifecycle:** {.start!} registers a single subscription block;
  # {.stop!} unsubscribes. Both are idempotent so the Plan 06 Railtie
  # can call `start!` once at boot without worrying about
  # double-subscription. {.started?} reports the current state.
  #
  # `lib/track_relay.rb` requires this file but does NOT call `start!`
  # — only the Railtie does, so non-Rails environments can opt in.
  module Dispatcher
    NOTIFICATION = "track_relay.event"

    class << self
      # Register the AS::Notifications subscription. Idempotent: calling
      # twice does not double-subscribe.
      #
      # @param notifier [#subscribe] defaults to ActiveSupport::Notifications
      # @return [Object] the subscription handle (opaque AS object)
      def start!(notifier = ActiveSupport::Notifications)
        return @subscription if @subscription
        @subscription = notifier.subscribe(NOTIFICATION) do |*, payload|
          dispatch(payload[:event])
        end
      end

      # Unsubscribe the AS::Notifications subscription. Idempotent — safe
      # to call when no subscription has been registered.
      #
      # @param notifier [#unsubscribe] defaults to ActiveSupport::Notifications
      # @return [void]
      def stop!(notifier = ActiveSupport::Notifications)
        return unless @subscription
        notifier.unsubscribe(@subscription)
        @subscription = nil
      end

      # @return [Boolean] whether a subscription is currently registered
      def started?
        !@subscription.nil?
      end

      private

      def dispatch(payload)
        errors = []
        TrackRelay.config.subscribers.each do |subscriber|
          # Subscribers::Base#handle returns nil on success or the
          # StandardError on failure (it never re-raises inline). For
          # non-Base subscribers that ignore that contract, the inline
          # rescue below preserves the "peers still run" invariant.
          result =
            begin
              subscriber.handle(payload)
            rescue => e
              if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
                Rails.logger.error(
                  "[track_relay] non-Base subscriber #{subscriber.class} raised inline: #{e.class}: #{e.message}"
                )
              end
              e
            end
          errors << result if result.is_a?(StandardError)
        end

        return if errors.empty?
        return if TrackRelay.config.swallow_subscriber_errors
        raise errors.first
      end
    end
  end
end
