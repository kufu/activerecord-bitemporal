require 'spec_helper'

RSpec.describe "transaction_at" do
  describe "fix `created_at` and `deleted_at`" do
    let(:company) { Company.create(name: "Company1") }
    define_method(:company_all) { Company.ignore_valid_datetime.within_deleted.bitemporal_for(company.id).order(:created_at) }

    before do
      # Created any records
      company.update!(name: "Company2")
      company.force_update { |it| it.update!(name: "Company3") }
    end

    context "updated" do
      it "prev.deleted_at to equal next.created_at" do
        company.update!(name: "NewCompany")
        expect(company_all[-3].deleted_at).to eq(company_all[-2].created_at)
                                         .and(eq(company_all[-1].created_at))
      end

      context "with `#force_update`" do
        it do
          company.force_update { |it| it.update!(name: "NewCompany") }
          expect(company_all[-2].deleted_at).to eq(company_all[-1].created_at)
        end
      end
    end

    context "deleted" do
      it do
        company.reload.destroy
        expect(company_all[-2].deleted_at).to eq(company_all[-1].created_at)
      end
    end
  end
end
