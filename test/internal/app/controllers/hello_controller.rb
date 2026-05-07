# frozen_string_literal: true

class HelloController < ApplicationController
  def show
    track :hello_world, message: params.fetch(:message, "hello")
    head :ok
  end
end
