class MerchantAlias < ApplicationRecord
  belongs_to :user

  validates :raw_name, presence: true
  validates :canonical_name, presence: true
  validates :raw_name, uniqueness: { scope: :user_id }
end
