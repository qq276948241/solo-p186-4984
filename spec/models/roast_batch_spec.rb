require 'spec_helper'

RSpec.describe RoastBatch, type: :model do
  describe 'validations' do
    it 'requires roast_quantity_grams' do
      batch = build(:roast_batch, roast_quantity_grams: nil)
      expect(batch).not_to be_valid
    end

    it 'requires roasted_at' do
      batch = build(:roast_batch, roasted_at: nil)
      expect(batch).not_to be_valid
    end

    it 'validates roast_quantity_grams > 0' do
      batch = build(:roast_batch, roast_quantity_grams: 0)
      expect(batch).not_to be_valid
    end
  end

  describe 'batch_number generation' do
    let(:bean) { create(:coffee_bean) }

    it 'generates a unique batch number on create' do
      batch = create(:roast_batch, coffee_bean: bean)
      expect(batch.batch_number).not_to be_nil
      expect(batch.batch_number).to match(/^RB\d+/)
    end

    it 'generates sequential batch numbers' do
      batch1 = create(:roast_batch, coffee_bean: bean)
      batch2 = create(:roast_batch, coffee_bean: bean)
      expect(batch2.batch_number).not_to eq(batch1.batch_number)
    end
  end

  describe 'auto stock addition' do
    let(:bean) { create(:coffee_bean, stock_grams: 1000) }

    it 'adds roasted quantity to stock after create' do
      create(:roast_batch, coffee_bean: bean, roast_quantity_grams: 2000)
      expect(bean.reload.stock_grams).to eq(3000)
    end
  end
end
