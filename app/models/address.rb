class Address < ActiveRecord::Base
  belongs_to :user
  has_many :orders, dependent: :nullify
  has_many :subscriptions, dependent: :nullify
  has_many :shipments, dependent: :nullify

  validates :recipient_name, presence: true
  validates :phone, presence: true
  validates :province, presence: true
  validates :city, presence: true
  validates :district, presence: true
  validates :detail, presence: true

  before_save :ensure_single_default

  def full_address
    "#{province}#{city}#{district}#{detail}"
  end

  def locked?
    locked
  end

  private

  def ensure_single_default
    return unless is_default?

    user.addresses.where.not(id: id).update_all(is_default: false)
  end
end
