# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Bitemporal::Visualizer do
  describe 'visuablize' do
    let(:time) { '2022-05-23 18:06:06.712' }
    around { |e| Timecop.freeze(time) { e.run } }
    subject(:figure) { described_class.visualize(employee) }

    context 'when it has never been updated' do
      let(:employee) { Employee.create! }

      it 'is a square' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |                                       | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +---------------------------------------+
                        |***************************************|
                        |***************************************|
                        |***************************************|
                        |***************************************|
                        |***************************************|
                        |***************************************|
                        |***************************************|
                        |***************************************|
                        |***************************************|
9999-12-31 00:00:00.000 +---------------------------------------+
EOS
      end
    end

    context 'when it has been updated once' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-06-23 18:06:06.712' do
          employee.update!(name: 'Jane')
          employee.reload
        end
      end

      it 'is 3 squares' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |                   | 2022-06-23 18:06:06.712
                        |                   |                   | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +---------------------------------------+
                        |                                       |
                        |                                       |
                        |                                       |
                        |                                       |
2022-06-23 18:06:06.712 +-------------------+-------------------+
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
9999-12-31 00:00:00.000 +-------------------+-------------------+
EOS
      end
    end

    context 'when it has been updated twice' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-06-01 18:06:06.712' do
          employee.update!(name: 'Jane')
        end

        Timecop.freeze '2022-06-23 18:06:06.712' do
          employee.update!(name: 'Mike')
          employee.reload
        end
      end

      it 'is 5 squares' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |    | 2022-06-01 18:06:06.712
                        |    |              | 2022-06-23 18:06:06.712
                        |    |              |                   | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +---------------------------------------+
                        |                                       |
2022-06-01 18:06:06.712 +----+----------------------------------+
                        |    |                                  |
                        |    |                                  |
2022-06-23 18:06:06.712 |    +--------------+-------------------+
                        |    |              |*******************|
                        |    |              |*******************|
                        |    |              |*******************|
                        |    |              |*******************|
9999-12-31 00:00:00.000 +----+--------------+-------------------+
EOS
      end
    end

    context 'if it has been updated at very short intervals' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-05-23 18:06:06.831' do
          employee.update!(name: 'Jane')
        end

        Timecop.freeze '2022-05-23 18:06:07.939' do
          employee.update!(name: 'Mike')
        end

        Timecop.freeze '2030-05-23 18:06:07.939' do
          employee.update!(name: 'John')
          employee.reload
        end
      end

      it 'is plotted in the smallest area' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        | | 2022-05-23 18:06:06.831
                        | | | 2022-05-23 18:06:07.939
                        | | |               | 2030-05-23 18:06:07.939
                        | | |               |                   | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +---------------------------------------+
                        |                                       |
2022-05-23 18:06:06.831 +-+-------------------------------------+
                        | |                                     |
2022-05-23 18:06:07.939 | +-+-----------------------------------+
                        | | |                                   |
2030-05-23 18:06:07.939 | | +---------------+-------------------+
                        | | |               |*******************|
                        | | |               |*******************|
                        | | |               |*******************|
9999-12-31 00:00:00.000 +-+-+---------------+-------------------+
EOS
      end
    end

    context 'when it has been updated as zero length (valid_from == valid_to || transaction_from == transaction_to)' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-06-01 18:06:06.712' do
          employee.update!(name: 'Jane')
        end

        Timecop.freeze '2022-06-23 18:06:06.712' do
          employee.update!(name: 'Mike')

          first, second = Employee.ignore_valid_datetime.bitemporal_for(employee).order(:valid_from)
          first.update_columns(valid_to: first.valid_from)
          second.update_columns(valid_from: first.valid_from)

          first, second = Employee.ignore_transaction_datetime.bitemporal_for(employee).order(:transaction_from)
          first.update_columns(transaction_to: first.transaction_from)
          second.update_columns(transaction_from: first.transaction_from)

          employee.reload
        end
      end

      it 'is plotted as zero length history' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |    | 2022-06-01 18:06:06.712
                        |    |              | 2022-06-23 18:06:06.712
                        |    |              |                   | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +#######################################+
                             |                                  |
2022-06-01 18:06:06.712 #    |                                  |
                        #    |                                  |
                        #    |                                  |
2022-06-23 18:06:06.712 #-------------------+-------------------+
                        #                   |*******************|
                        #                   |*******************|
                        #                   |*******************|
                        #                   |*******************|
9999-12-31 00:00:00.000 #-------------------+-------------------+
EOS
      end
    end

    context 'when it has been updated as zero area (valid_from == valid_to && transaction_from == transaction_to)' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-06-01 18:06:06.712' do
          employee.update!(name: 'Jane')

          first, second, third = Employee.ignore_bitemporal_datetime.bitemporal_for(employee).order(:transaction_from, :valid_from)
          first.update_columns(valid_to: first.valid_from, transaction_to: first.transaction_from)
          second.update_columns(transaction_from: first.transaction_from)
          third.update_columns(transaction_from: first.transaction_from)

          employee.reload
        end
      end

      it 'is plotted as zero area history' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |                   | 2022-06-01 18:06:06.712
                        |                   |                   | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 #-------------------+-------------------+
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
                        |                   |*******************|
9999-12-31 00:00:00.000 +-------------------+-------------------+
EOS
      end
    end

    context 'when it has been updated twice with other valid times' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-06-01 18:06:06.712' do
          ActiveRecord::Bitemporal.valid_at '2022-04-23 18:06:06.712' do
            employee.update!(name: 'Jane')
          end
        end

        Timecop.freeze '2022-06-23 18:06:06.712' do
          ActiveRecord::Bitemporal.valid_at '2022-05-01 18:06:06.712' do
            employee.reload.update!(name: 'Mike')
            employee.reload
          end
        end
      end

      it 'is 4 squares' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-04-23 18:06:06.712
                        |    | 2022-05-01 18:06:06.712
                        |    |              | 2022-05-23 18:06:06.712
                        |    |              |                   | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712                     +-------------------+
                                            |                   |
2022-06-01 18:06:06.712 +-------------------+                   |
                        |                   |                   |
                        |                   |                   |
2022-06-23 18:06:06.712 +----+--------------+                   |
                        |    |**************|                   |
                        |    |**************|                   |
                        |    |**************|                   |
                        |    |**************|                   |
9999-12-31 00:00:00.000 +----+--------------+-------------------+
EOS
      end
    end

    context 'when it has been updated so that it is not continuous' do
      let(:employee) do
        employee = Employee.create!

        Timecop.freeze '2022-06-23 18:06:06.712' do
          employee.update!(name: 'Jane')
          employee.reload

          employee.update_columns(valid_from: employee.valid_from + 1.second, transaction_from: employee.transaction_from + 1.second)
          employee
        end
      end

      it 'is 3 squares with blanks' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |                  | 2022-06-23 18:06:06.712
                        |                  | | 2022-06-23 18:06:07.712
                        |                  | |                  | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +---------------------------------------+
                        |                                       |
                        |                                       |
                        |                                       |
2022-06-23 18:06:06.712 +------------------+--------------------+
                        |                  |
2022-06-23 18:06:07.712 |                  | +------------------+
                        |                  | |******************|
                        |                  | |******************|
                        |                  | |******************|
9999-12-31 00:00:00.000 +------------------+ +------------------+
EOS
      end
    end

    context 'when it has been deleted' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-06-23 18:06:06.712' do
          employee.destroy!
          employee
        end
      end

      it 'is 2 squares' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |                   | 2022-06-23 18:06:06.712
                        |                   |                   | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +---------------------------------------+
                        |                                       |
                        |                                       |
                        |                                       |
                        |                                       |
2022-06-23 18:06:06.712 +-------------------+-------------------+
                        |*******************|
                        |*******************|
                        |*******************|
                        |*******************|
9999-12-31 00:00:00.000 +-------------------+
EOS
      end
    end

    context 'whe it has been force updated' do
      let(:employee) do
        employee = Employee.create!
        Timecop.freeze '2022-06-23 18:06:06.712' do
          employee.force_update { |employee| employee.update!(name: 'Jane') }
          employee.reload
        end
      end

      it 'is 2 squares' do
        expect(figure).to eq <<~EOS.chomp
                        | 2022-05-23 18:06:06.712
                        |                                       | 9999-12-31 00:00:00.000
2022-05-23 18:06:06.712 +---------------------------------------+
                        |                                       |
                        |                                       |
                        |                                       |
                        |                                       |
2022-06-23 18:06:06.712 +---------------------------------------+
                        |***************************************|
                        |***************************************|
                        |***************************************|
                        |***************************************|
9999-12-31 00:00:00.000 +---------------------------------------+
EOS
      end
    end
  end
end
