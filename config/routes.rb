Rails.application.routes.draw do
  root "uploads#new"

  resources :uploads, only: [:new, :create, :show]
  post "uploads/:id/analyze", to: "uploads#analyze", as: :analyze_upload
  patch "uploads/:id/update_parsed_row/:row_index", to: "uploads#update_parsed_row", as: :update_parsed_row
end