class Upload < ApplicationRecord
  belongs_to :user
  has_one_attached :file
  has_many :subscriptions, dependent: :destroy
end