Rails.application.routes.draw do
  root "pages#home"

  devise_for :users

  resources :uploads, only: [:index, :new, :create, :show, :destroy]
  post "uploads/:id/analyze", to: "uploads#analyze", as: :analyze_upload
  patch "uploads/:id/update_parsed_row/:row_index", to: "uploads#update_parsed_row", as: :update_parsed_row
  post "uploads/:id/recalculate", to: "uploads#recalculate", as: :recalculate_upload

  get "uploads/:id/export_subscriptions_csv", to: "uploads#export_subscriptions_csv", as: :export_subscriptions_csv
  get "uploads/:id/export_calendar", to: "uploads#export_calendar", as: :export_calendar
  post "uploads/:id/enrich_subscriptions", to: "uploads#enrich_subscriptions", as: :enrich_subscriptions
end