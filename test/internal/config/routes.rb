# frozen_string_literal: true

Rails.application.routes.draw do
  get "/articles/:id", to: "articles#show", as: :article
end
