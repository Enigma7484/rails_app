Rails.application.routes.draw do
  root "uploads#new"

  resources :uploads, only: [:new, :create, :show]
  post "uploads/:id/analyze", to: "uploads#analyze", as: :analyze_upload
end