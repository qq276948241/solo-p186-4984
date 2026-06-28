require 'spec_helper'

RSpec.describe CoffeeBean, type: :model do
  describe 'validations' do
    it 'requires a name' do
      bean = build(:coffee_bean, name: nil)
      expect(bean).not_to be_valid
    end

    it 'requires origin' do
      bean = build(:coffee_bean, origin: nil)
      expect(bean).not_to be_valid
    end

    it 'requires roast_level' do
      bean = build(:coffee_bean, roast_level: nil)
      expect(bean).not_to be_valid
    end

    it 'requires flavor_description' do
      bean = build(:coffee_bean, flavor_description: nil)
      expect(bean).not_to be_valid
    end

    it 'requires stock_grams' do
      bean = build(:coffee_bean, stock_grams: nil)
      expect(bean).not_to be_valid
    end

    it 'requires price_per_100g' do
      bean = build(:coffee_bean, price_per_100g: nil)
      expect(bean).not_to be_valid
    end

    it 'validates roast_level inclusion' do
      bean = build(:coffee_bean, roast_level: 'invalid')
      expect(bean).not_to be_valid
    end

    it 'validates stock_grams >= 0' do
      bean = build(:coffee_bean, stock_grams: -1)
      expect(bean).not_to be_valid
    end

    it 'validates price_per_100g > 0' do
      bean = build(:coffee_bean, price_per_100g: 0)
      expect(bean).not_to be_valid
    end
  end

  describe 'scopes' do
    let!(:active_bean) { create(:coffee_bean, active: true, stock_grams: 100) }
    let!(:inactive_bean) { create(:coffee_bean, active: false, stock_grams: 100) }
    let!(:out_of_stock) { create(:coffee_bean, active: true, stock_grams: 0) }

    it '.active returns only active beans' do
      expect(described_class.active).to include(active_bean, out_of_stock)
      expect(described_class.active).not_to include(inactive_bean)
    end

    it '.in_stock returns only beans with stock' do
      expect(described_class.in_stock).to include(active_bean, inactive_bean)
      expect(described_class.in_stock).not_to include(out_of_stock)
    end
  end

  describe '#roast_level_display' do
    it 'returns the Chinese name for roast level' do
      bean = build(:coffee_bean, roast_level: 'light')
      expect(bean.roast_level_display).to eq('浅烘焙')
    end
  end

  describe '#adjust_stock!' do
    let(:bean) { create(:coffee_bean, stock_grams: 1000) }

    it 'increases stock' do
      bean.adjust_stock!(500)
      expect(bean.reload.stock_grams).to eq(1500)
    end

    it 'decreases stock' do
      bean.adjust_stock!(-300)
      expect(bean.reload.stock_grams).to eq(700)
    end

    it 'raises error when stock would go negative' do
      expect { bean.adjust_stock!(-1500) }.to raise_error(ArgumentError, '库存不足')
    end
  end

  describe '#price_for' do
    let(:bean) { create(:coffee_bean, price_per_100g: 68) }

    it 'calculates price for given grams' do
      expect(bean.price_for(250)).to eq(170.0)
      expect(bean.price_for(500)).to eq(340.0)
    end
  end
end
