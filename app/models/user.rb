class User < ApplicationRecord
  has_many :uploads, dependent: :destroy
  has_many :merchant_aliases, dependent: :destroy

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
