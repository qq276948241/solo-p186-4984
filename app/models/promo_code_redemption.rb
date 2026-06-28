class PromoCodeRedemption < ActiveRecord::Base
  belongs_to :promotion_code
  belongs_to :user
  belongs_to :order, optional: true
  belongs_to :subscription, optional: true

  validates :promotion_code_id, uniqueness: { scope: :user_id, message: '该优惠码您已使用过' }
  validates :redeemed_at, presence: true
end
