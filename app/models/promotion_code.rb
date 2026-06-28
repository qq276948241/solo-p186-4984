class PromotionCode < ActiveRecord::Base
  has_many :orders, dependent: :nullify
  has_many :subscriptions, dependent: :nullify

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :discount_type, presence: true, inclusion: { in: %w[fixed percentage] }
  validates :discount_value, presence: true, numericality: { greater_than: 0 }
  validates :max_uses, presence: true, numericality: { greater_than_or_equal_to: 1 }
  validates :used_count, numericality: { greater_than_or_equal_to: 0 }

  DISCOUNT_TYPES = {
    'fixed' => '固定金额',
    'percentage' => '折扣百分比'
  }.freeze

  scope :active, -> { where(active: true) }
  scope :not_expired, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :with_uses_remaining, -> { where('used_count < max_uses') }
  scope :valid_now, -> { active.not_expired.with_uses_remaining }

  def self.lookup_and_validate(code)
    return [nil, nil] unless code.present?

    promo = find_by('UPPER(code) = UPPER(?)', code.strip)
    return [nil, '优惠码不存在'] unless promo
    return [nil, '优惠码已停用'] unless promo.active?
    return [nil, '优惠码已过期'] if promo.expired?
    return [nil, '优惠码已用完'] if promo.used_up?

    [promo, nil]
  end

  def valid_for_use?
    active? &&
      (expires_at.nil? || expires_at > Time.current) &&
      used_count < max_uses
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def used_up?
    used_count >= max_uses
  end

  def discount_type_display
    DISCOUNT_TYPES[discount_type] || discount_type
  end

  def discount_description
    case discount_type
    when 'fixed'
      "减 ¥#{discount_value.to_f}"
    when 'percentage'
      "打 #{(10 - discount_value / 10)} 折"
    else
      ''
    end
  end

  def calculate_discount(original_total)
    return 0 unless valid_for_use?

    case discount_type
    when 'fixed'
      [discount_value.to_f, original_total.to_f].min
    when 'percentage'
      (original_total.to_f * discount_value.to_f / 100.0).round(2)
    else
      0
    end
  end

  def apply_to(original_total)
    discount = calculate_discount(original_total)
    [original_total.to_f - discount, discount]
  end

  def record_use!
    return false unless valid_for_use?

    increment!(:used_count)
    true
  end

  def uses_remaining
    max_uses - used_count
  end
end
