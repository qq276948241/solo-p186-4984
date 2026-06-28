class Order < ActiveRecord::Base
  belongs_to :user
  belongs_to :address
  belongs_to :promotion_code, optional: true
  has_many :order_items, dependent: :destroy
  has_many :shipments, dependent: :nullify

  accepts_nested_attributes_for :order_items

  validates :status, presence: true, inclusion: { in: %w[pending processing shipped delivered cancelled] }
  validates :order_type, presence: true, inclusion: { in: %w[one_time subscription] }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }

  STATUSES = {
    'pending' => '待处理',
    'processing' => '处理中',
    'shipped' => '已发货',
    'delivered' => '已送达',
    'cancelled' => '已取消'
  }.freeze

  scope :history_for, ->(user) { where(user: user).order(created_at: :desc) }

  def status_display
    STATUSES[status] || status
  end

  def subtotal
    order_items.sum(&:subtotal)
  end

  def apply_promotion_code!(code)
    promo = PromotionCode.find_by('UPPER(code) = UPPER(?)', code)
    return false unless promo&.valid_for_use?

    self.promotion_code = promo
    original_total = subtotal
    self.discount_amount = promo.calculate_discount(original_total)
    self.total_amount = (original_total - discount_amount).round(2)
    self.total_amount = 0 if total_amount < 0
    save!
    true
  end

  def calculate_total!
    original = subtotal
    self.discount_amount = if promotion_code&.valid_for_use?
                             promotion_code.calculate_discount(original)
                           else
                             0
                           end
    self.total_amount = (original - discount_amount).round(2)
    self.total_amount = 0 if total_amount < 0
    save!
  end
end
