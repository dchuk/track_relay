# frozen_string_literal: true

require "ostruct"

class WelcomeEmailJob < ActiveJob::Base
  include TrackRelay::JobTracking

  def perform(user_id, visitor_token)
    user = OpenStruct.new(id: user_id, last_visitor_token: visitor_token)
    TrackRelay::Current.set(user: user) do
      track :welcome_email_sent,
        user_id: user_id,
        visitor_token: visitor_token,
        template: "v3"
    end
  end
end
