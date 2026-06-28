require 'spec_helper'

RSpec.describe Subscription, type: :model do
  describe 'validations' do
    it 'requires frequency' do
      sub = build(:subscription, frequency: nil)
      expect(sub).not_to be_valid
    end

    it 'requires status' do
      sub = build(:subscription, status: nil)
      expect(sub).not_to be_valid
    end

    it 'requires start_date' do
      sub = build(:subscription, start_date: nil)
      expect(sub).not_to be_valid
    end

    it 'requires next_delivery_date' do
      sub = build(:subscription, next_delivery_date: nil)
      expect(sub).not_to be_valid
    end

    it 'validates frequency inclusion' do
      sub = build(:subscription, frequency: 'invalid')
      expect(sub).not_to be_valid
    end

    it 'validates status inclusion' do
      sub = build(:subscription, status: 'invalid')
      expect(sub).not_to be_valid
    end

    it 'validates skip_next_count >= 0' do
      sub = build(:subscription, skip_next_count: -1)
      expect(sub).not_to be_valid
    end
  end

  describe 'frequency helpers' do
    it 'returns correct days for weekly' do
      sub = build(:subscription, frequency: 'weekly')
      expect(sub.frequency_days).to eq(7)
      expect(sub.frequency_display).to eq('每周')
    end

    it 'returns correct days for biweekly' do
      sub = build(:subscription, frequency: 'biweekly')
      expect(sub.frequency_days).to eq(14)
      expect(sub.frequency_display).to eq('双周')
    end

    it 'returns correct days for monthly' do
      sub = build(:subscription, frequency: 'monthly')
      expect(sub.frequency_days).to eq(30)
      expect(sub.frequency_display).to eq('每月')
    end
  end

  describe 'status transitions' do
    let(:sub) { create(:subscription, status: 'active') }

    it '#pause! pauses the subscription' do
      sub.pause!
      expect(sub.reload.status).to eq('paused')
    end

    it '#resume! resumes a paused subscription' do
      sub.update!(status: 'paused')
      sub.resume!
      expect(sub.reload.status).to eq('active')
    end

    it '#cancel! cancels the subscription' do
      sub.cancel!
      expect(sub.reload.status).to eq('cancelled')
    end
  end

  describe '#skip_next!' do
    let(:sub) { create(:subscription, skip_next_count: 0) }

    it 'increments skip_next_count' do
      sub.skip_next!
      expect(sub.reload.skip_next_count).to eq(1)
      sub.skip_next!
      expect(sub.reload.skip_next_count).to eq(2)
    end
  end

  describe '#calculate_next_delivery_date!' do
    let(:start_date) { Date.new(2024, 1, 1) }

    it 'advances weekly with no skips' do
      sub = create(:subscription,
        frequency: 'weekly',
        start_date: start_date,
        next_delivery_date: start_date,
        skip_next_count: 0)
      sub.calculate_next_delivery_date!
      expect(sub.reload.next_delivery_date).to eq(Date.new(2024, 1, 8))
    end

    it 'advances weekly with 1 skip' do
      sub = create(:subscription,
        frequency: 'weekly',
        start_date: start_date,
        next_delivery_date: start_date,
        skip_next_count: 1)
      sub.calculate_next_delivery_date!
      expect(sub.reload.next_delivery_date).to eq(Date.new(2024, 1, 15))
    end

    it 'advances biweekly' do
      sub = create(:subscription,
        frequency: 'biweekly',
        start_date: start_date,
        next_delivery_date: start_date,
        skip_next_count: 0)
      sub.calculate_next_delivery_date!
      expect(sub.reload.next_delivery_date).to eq(Date.new(2024, 1, 15))
    end

    it 'resets skip_next_count' do
      sub = create(:subscription,
        frequency: 'weekly',
        start_date: start_date,
        next_delivery_date: start_date,
        skip_next_count: 2)
      sub.calculate_next_delivery_date!
      expect(sub.reload.skip_next_count).to eq(0)
    end
  end

  describe '#lock_address!' do
    let(:address) { create(:address, locked: false) }
    let(:sub) { create(:subscription, address: address) }

    it 'locks the associated address' do
      sub.lock_address!
      expect(address.reload.locked?).to be true
    end
  end

  describe 'scopes' do
    let(:today) { Date.today }

    it '.active_for_delivery returns eligible subscriptions' do
      s1 = create(:subscription, status: 'active', next_delivery_date: today)
      s2 = create(:subscription, status: 'active', next_delivery_date: today + 1)
      s3 = create(:subscription, status: 'paused', next_delivery_date: today)

      result = described_class.active_for_delivery(today)
      expect(result).to include(s1)
      expect(result).not_to include(s2, s3)
    end
  end
end
