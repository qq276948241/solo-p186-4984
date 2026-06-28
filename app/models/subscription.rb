class Subscription < ActiveRecord::Base
  belongs_to :user
  belongs_to :address
  belongs_to :promotion_code, optional: true
  has_many :subscription_items, dependent: :destroy
  has_many :shipments, dependent: :nullify

  accepts_nested_attributes_for :subscription_items

  validates :frequency, presence: true, inclusion: { in: %w[weekly biweekly monthly] }
  validates :status, presence: true, inclusion: { in: %w[active paused cancelled] }
  validates :start_date, presence: true
  validates :next_delivery_date, presence: true
  validates :skip_next_count, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }

  FREQUENCIES = {
    'weekly' => { name: '每周', days: 7 },
    'biweekly' => { name: '双周', days: 14 },
    'monthly' => { name: '每月', days: 30 }
  }.freeze

  STATUSES = {
    'active' => '生效中',
    'paused' => '已暂停',
    'cancelled' => '已取消'
  }.freeze

  scope :active_for_delivery, ->(date) {
    where(status: 'active').where('next_delivery_date <= ?', date)
  }

  def frequency_display
    FREQUENCIES.dig(frequency, :name) || frequency
  end

  def status_display
    STATUSES[status] || status
  end

  def frequency_days
    FREQUENCIES.dig(frequency, :days) || 7
  end

  def pause!
    update!(status: 'paused')
  end

  def resume!
    update!(status: 'active')
  end

  def cancel!
    update!(status: 'cancelled')
  end

  def skip_next!
    increment!(:skip_next_count)
  end

  def calculate_next_delivery_date!
    days_to_add = frequency_days * (skip_next_count + 1)
    new_date = next_delivery_date + days_to_add.days
    update!(next_delivery_date: new_date, skip_next_count: 0)
  end

  def subtotal
    subscription_items.sum(&:subtotal)
  end

  def apply_promotion_code!(code)
    promo = PromotionCode.find_by('UPPER(code) = UPPER(?)', code)
    return false unless promo&.valid_for_use?

    self.promotion_code = promo
    original_total = subtotal
    self.discount_amount = promo.calculate_discount(original_total)
    self.total_amount_per_delivery = (original_total - discount_amount).round(2)
    self.total_amount_per_delivery = 0 if total_amount_per_delivery < 0
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
    self.total_amount_per_delivery = (original - discount_amount).round(2)
    self.total_amount_per_delivery = 0 if total_amount_per_delivery < 0
    save!
  end

  def lock_address!
    address.update!(locked: true)
  end
end
