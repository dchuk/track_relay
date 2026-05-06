# frozen_string_literal: true

class ArticlesController < ApplicationController
  def show
    track :article_viewed, article_id: params[:id].to_i, slug: "test-slug"
    head :ok
  end
end
