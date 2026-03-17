class User < ApplicationRecord
  has_many :uploads, dependent: :destroy

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end