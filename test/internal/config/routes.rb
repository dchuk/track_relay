# frozen_string_literal: true

Rails.application.routes.draw do
  get "/articles/:id", to: "articles#show", as: :article
  get "/hello", to: "hello#show", as: :hello
end
