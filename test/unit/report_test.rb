require 'test_helper'

class ReportTest < ActiveSupport::TestCase
  def setup
    User.current = users :admin
  end

  test "should expire reports created 1 week ago" do
    report_count = 3
    Message.delete_all
    Source.delete_all
    FactoryGirl.create_list(:report, report_count, :with_logs)
    FactoryGirl.create_list(:report, report_count, :with_logs, :old_report)
    assert Report.count > report_count*2
    assert_difference('Report.count', -1*report_count) do
      assert_difference(['Log.count', 'Message.count', 'Source.count'], -1*report_count*5) do
        Report.expire
      end
    end
  end

  describe '.my_reports' do
    setup do
      @target_host = FactoryGirl.create(:host, :with_hostgroup)
      @target_reports = FactoryGirl.create_pair(:config_report, host: @target_host)
      @other_host = FactoryGirl.create(:host, :with_hostgroup)
      @other_reports = FactoryGirl.create_pair(:report, host: @other_host)
    end

    test 'returns all reports for admin' do
      as_admin do
        assert_empty (@target_reports + @other_reports).map(&:id) - Report.my_reports.map(&:id)
      end
    end

    test 'returns visible reports for unlimited user' do
      user_role = FactoryGirl.create(:user_user_role)
      FactoryGirl.create(:filter, :role => user_role.role, :permissions => Permission.where(:name => 'view_hosts'), :unlimited => true)
      collection = as_user(user_role.owner) { Report.my_reports }
      assert_empty (@target_reports + @other_reports).map(&:id) - collection.map(&:id)
    end

    test 'returns visible reports for filtered user' do
      user_role = FactoryGirl.create(:user_user_role)
      FactoryGirl.create(:filter, :role => user_role.role, :permissions => Permission.where(:name => 'view_hosts'), :search => "hostgroup_id = #{@target_host.hostgroup_id}")
      as_user user_role.owner do
        assert_equal @target_reports.map(&:id).sort, Report.my_reports.map(&:id).sort
      end
    end

    test "only return reports from host in user's taxonomies" do
      user_role = FactoryGirl.create(:user_user_role)
      FactoryGirl.create(:filter, :role => user_role.role, :permissions => Permission.where(:name => 'view_hosts'), :search => "hostgroup_id = #{@target_host.hostgroup_id}")

      orgs = FactoryGirl.create_pair(:organization)
      locs = FactoryGirl.create_pair(:location)
      @target_host.update_attributes(:location => locs.last, :organization => orgs.last)
      @target_host.hostgroup.update_attributes(:locations => [locs.last], :organizations => [orgs.last])

      user_role.owner.update_attributes(:locations => [locs.first], :organizations => [orgs.first])
      as_user user_role.owner do
        assert_equal [], Report.my_reports.map(&:id).sort
      end

      user_role.owner.update_attributes(:locations => [locs.last], :organizations => [orgs.last])
      as_user user_role.owner do
        assert_equal @target_reports.map(&:id).sort, Report.my_reports.map(&:id).sort
      end
    end

    test "only return reports from host in admin's currently selected taxonomy" do
      user = FactoryGirl.create(:user, :admin)
      orgs = FactoryGirl.create_pair(:organization)
      locs = FactoryGirl.create_pair(:location)
      @target_host.update_attributes(:location => locs.last, :organization => orgs.last)

      as_user user do
        in_taxonomy(orgs.first) do
          in_taxonomy(locs.first) do
            refute_includes Report.my_reports, @target_reports.first
          end
        end

        in_taxonomy(orgs.last) do
          in_taxonomy(locs.last) do
            assert_includes Report.my_reports, @target_reports.first
          end
        end
      end
    end
  end

  describe 'Report STI' do
    test "Report has default type" do
      report = Report.new
      assert_equal('ConfigReport', report.type)
    end

    test '.expire should delete only the class which calls it' do
      FactoryGirl.create_list(:config_report, 5, :old_report)
      FactoryGirl.create_list(:report, 5, :old_report, :type => 'TestReport')
      TestReport.expire
      refute(TestReport.all.any?)
      assert(ConfigReport.all.any?)
    end

    test '#metrics with metrics should return empty hash' do
      report = ConfigReport.import read_json_fixture('report-empty.json')
      assert_equal({}, report.metrics)
      report = ConfigReport.import read_json_fixture('report-no-logs.json')
      refute_equal({}, report.metrics)
      assert_equal({'success' => 1, 'total' => 1, 'failure' =>0}, report.metrics['events'])
      report = TestReport.new
      assert_equal({}, report.metrics)
    end

    test 'can view host reports as non-admin user' do
      report = FactoryGirl.create(:config_report)
      setup_user('view', 'hosts', "name = #{report.host.name}")
      setup_user('view',  'config_reports')

      assert_includes ConfigReport.authorized('view_config_reports').my_reports, report
    end
  end
end

class TestReport < Report; end
