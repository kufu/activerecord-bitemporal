# frozen_string_literal: true

require "spec_helper"

GlobalID.app = "test-app"

RSpec.describe "GlobalID" do
  describe "#to_globalid" do
    context "when BTDM" do
      let(:company) { Company.create!(name: "Company1").tap { _1.update!(name: "Company2") } }

      it "app name is bitemporal" do
        expect(company.to_global_id).to eq GlobalID.new("gid://bitemporal/Company/#{company.bitemporal_id}")
      end
    end

    context "when non BTDM" do
      let(:non_btdm_class) do
        Class.new(CompanyWithoutBitemporal) do
          include GlobalID::Identification

          def self.name
            "CompanyWithoutBitemporalGID"
          end
        end
      end
      let(:company) { non_btdm_class.create!(name: "Company1") }

      it "app name is default" do
        expect(company.to_global_id).to eq GlobalID.new("gid://test-app/CompanyWithoutBitemporalGID/#{company.id}")
      end
    end
  end

  describe "#to_gid" do
    context "when BTDM" do
      let(:company) { Company.create!(name: "Company1").tap { _1.update!(name: "Company2") } }

      it "app name is bitemporal" do
        expect(company.to_gid).to eq GlobalID.new("gid://bitemporal/Company/#{company.bitemporal_id}")
      end
    end

    context "when non BTDM" do
      let(:non_btdm_class) do
        Class.new(CompanyWithoutBitemporal) do
          include GlobalID::Identification

          def self.name
            "CompanyWithoutBitemporalGID"
          end
        end
      end
      let(:company) { non_btdm_class.create!(name: "Company1") }

      it "app name is default" do
        expect(company.to_gid).to eq GlobalID.new("gid://test-app/CompanyWithoutBitemporalGID/#{company.id}")
      end
    end
  end

  describe "GlobalID::Locator.locate" do
    let(:company) do
      Company.create!(name: "Company1").tap do |m|
        m.update!(name: "Company2")
        m.update!(name: "Company3")
      end
    end
    let(:gid) { company.to_global_id }

    it "can find current record" do
      expect(GlobalID::Locator.locate(gid).name).to eq "Company3"
    end
  end
end
