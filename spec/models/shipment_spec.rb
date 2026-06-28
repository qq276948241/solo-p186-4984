require 'spec_helper'

RSpec.describe Shipment, type: :model do
  describe 'validations' do
    it 'requires status' do
      shipment = build(:shipment, status: nil)
      expect(shipment).not_to be_valid
    end

    it 'requires scheduled_date' do
      shipment = build(:shipment, scheduled_date: nil)
      expect(shipment).not_to be_valid
    end

    it 'validates status inclusion' do
      shipment = build(:shipment, status: 'invalid')
      expect(shipment).not_to be_valid
    end
  end

  describe 'status transitions' do
    let(:batch) { create(:roast_batch) }
    let(:address) { create(:address) }
    let(:order) { create(:order, status: 'pending') }
    let(:shipment) { create(:shipment, roast_batch: batch, address: address, order: order, status: 'pending') }

    it '#mark_shipped! marks as shipped' do
      shipment.mark_shipped!
      expect(shipment.reload.status).to eq('shipped')
      expect(shipment.shipped_at).not_to be_nil
      expect(order.reload.status).to eq('shipped')
    end

    it '#mark_delivered! marks as delivered' do
      shipment.mark_delivered!
      expect(shipment.reload.status).to eq('delivered')
      expect(shipment.delivered_at).not_to be_nil
      expect(order.reload.status).to eq('delivered')
      expect(order.delivered_at).not_to be_nil
    end

    it '#cancel! cancels the shipment' do
      shipment.cancel!
      expect(shipment.reload.status).to eq('cancelled')
    end
  end

  describe 'recipient info' do
    let(:address) { create(:address, recipient_name: '张三', province: '浙江省', city: '杭州市', district: '西湖区', detail: '文三路 123 号') }
    let(:shipment) { create(:shipment, address: address) }

    it '#recipient_name returns address recipient' do
      expect(shipment.recipient_name).to eq('张三')
    end

    it '#shipping_address returns full address' do
      expect(shipment.shipping_address).to include('浙江省', '杭州市', '西湖区', '文三路 123 号')
    end
  end

  describe 'scopes' do
    let!(:pending) { create(:shipment, status: 'pending') }
    let!(:shipped) { create(:shipment, status: 'shipped') }
    let!(:today) { create(:shipment, scheduled_date: Date.today) }
    let!(:tomorrow) { create(:shipment, scheduled_date: Date.tomorrow) }

    it '.pending returns only pending shipments' do
      result = described_class.pending
      expect(result).to include(pending)
      expect(result).not_to include(shipped)
    end

    it '.for_date returns shipments for given date' do
      result = described_class.for_date(Date.today)
      expect(result).to include(today)
      expect(result).not_to include(tomorrow)
    end
  end
end
