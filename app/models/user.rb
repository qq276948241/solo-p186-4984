class User < ActiveRecord::Base
  has_many :addresses, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :subscriptions, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :role, inclusion: { in: %w[customer admin] }

  ROLES = %w[customer admin].freeze

  def admin?
    role == 'admin'
  end

  def customer?
    role == 'customer'
  end

  def default_address
    addresses.find_by(is_default: true) || addresses.first
  end
end
