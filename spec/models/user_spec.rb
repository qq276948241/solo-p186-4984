require 'spec_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it 'requires a name' do
      user = build(:user, name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:name]).to include("can't be blank")
    end

    it 'requires an email' do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it 'requires a unique email' do
      create(:user, email: 'test@example.com')
      user = build(:user, email: 'test@example.com')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include('has already been taken')
    end

    it 'validates role inclusion' do
      user = build(:user, role: 'invalid')
      expect(user).not_to be_valid
    end
  end

  describe 'roles' do
    it 'identifies admins' do
      admin = create(:admin)
      expect(admin.admin?).to be true
      expect(admin.customer?).to be false
    end

    it 'identifies customers' do
      customer = create(:user)
      expect(customer.customer?).to be true
      expect(customer.admin?).to be false
    end
  end

  describe '#default_address' do
    it 'returns the default address' do
      user = create(:user)
      addr1 = create(:address, user: user, is_default: true)
      create(:address, user: user, is_default: false)

      expect(user.default_address).to eq(addr1)
    end

    it 'returns first address if no default' do
      user = create(:user)
      addr1 = create(:address, user: user, is_default: false)

      expect(user.default_address).to eq(addr1)
    end
  end

  describe 'associations' do
    it 'has many addresses' do
      user = create(:user)
      addr = create(:address, user: user)
      expect(user.addresses).to include(addr)
    end

    it 'destroys addresses when user destroyed' do
      user = create(:user)
      create(:address, user: user)
      expect { user.destroy }.to change(Address, :count).by(-1)
    end
  end
end
