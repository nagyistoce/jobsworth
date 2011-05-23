require 'spec_helper'

describe Task do

  describe "open scope" do

    let(:open_task)        { Task.make(:status => Task::OPEN) }
    let(:duplicated_task)  { Task.make(:status => Task::DUPLICATE) }
    let(:closed_task)      { Task.make(:status => Task::CLOSED) }

    it "should only return tasks with resolution open" do
      Task.open.should include(open_task)
      Task.open.should_not include(duplicated_task)
      Task.open.should_not include(closed_task) 
    end
  end

  it "should create a new instance given valid attributes" do
    expect { 
      Task.make
    }.to_not raise_error
  end

  describe "associations" do
    before(:each) do
      @task   = Task.make
    end
  
    it "should create new owner using 'owners' association" do
      new_owner = User.make
      @task.owners << new_owner
      @task.reload
      @task.owners.should include(new_owner)
    end

    it "should include all the owners in the 'users' association" do
      some_user     = User.make
      another_user  = User.make
      @task.owners << some_user
      @task.owners << another_user
      @task.users.should include(some_user)
      @task.users.should include(another_user)
    end

    it "should create a new watcher through the 'watchers' association" do
      new_watcher = User.make
      @task.watchers << new_watcher
      @task.reload
      @task.watchers.should include(new_watcher)
    end

    it "should include all the watchers in the 'users' association" do
      some_user  = User.make
      @task.watchers << some_user
      @task.watchers.should include(some_user)
    end

    it "should include owner's task_user join model in linked_user_notifications"
  end

  describe "access scopes" do
    before(:each) do
      company = Company.make
      3.times { Project.make(:company=>company)}
      @user = User.make(:company=> company)
      [0,1].each do |i|
        @user.projects << company.projects[i]
        2.times { company.projects[i].tasks.make(:company=>company, :users=>[@user]) }
        company.projects[i].tasks.make(:company=>company)
      end
      company.projects.last.tasks.make
      Project.make.tasks.make
    end

    describe "accessed_by(user)" do
      it "should return tasks only from user's company" do
        company_tasks           = @user.company.tasks
        tasks_accessed_by_user  = Task.accessed_by(@user) 
        company_tasks.should include *tasks_accessed_by_user
      end
  
      context "when the user doesn't have can_see_unwatched permission" do
        it "should return only watched tasks" do
          permission = @user.project_permissions.first
          permission.update_attributes(:can_see_unwatched => 0)
          @user.reload
          Task.accessed_by(@user).each do |task|
            @user.should be_can(task.project, 'see_unwatched') unless task.users.include?(@user)
          end
        end
      end

      it "should the tasks from completed projects" do
        completed_project = @user.projects.first
        completed_project.update_attributes(:completed_at => 1.day.ago.utc)
        tasks_accessed_by_user = Task.accessed_by(@user)

        tasks_accessed_by_user.should_not include *completed_project.tasks
      end
    end

    context "all_accessed_by(user)" do
      it "should return tasks only from user's company" do
        Task.all_accessed_by(@user).each do |task|
          @user.company.tasks.should include(task)
        end
      end

      it "should return only watched tasks if user not have can_see_unwatched permission" do
        permission=@user.project_permissions.first
        permission.remove('see_unwatched')
        permission.save!
        @user.reload
        Task.all_accessed_by(@user).each do |task|
          @user.should be_can(task.project, 'see_unwatched') unless task.users.include?(@user)
        end
      end

      it "should return tasks from all users projects, even completed" do
        project= @user.projects.first
        project.completed_at= Time.now.utc
        project.save!
        Task.all_accessed_by(@user).should == 
          Task.all(:conditions=> ["tasks.project_id in(?)", @user.all_project_ids])
      end
    end
  end

  context "#notify_emails_array" do "should return array of stripped emails(from notify_emails field), splited by space, comma or new line"
    before :each do
      @task= Task.make( :notify_emails => "email.one@domain.com    email.two@domain.com.ua, anotheremail@mail.com\nanother@some.domain.com\r\nemail@gmasii.cm")
    end
    it "should return array of emails(from notify_emails field), splited by space, comma or new line" do
      @task.notify_emails_array.should have(5).emails
    end
    it "should strip each email" do
      @task.notify_emails_array.each { |email| email.should == email.strip }
    end
  end
  describe "task_property_values attributes assignment using Task#properties=(params) method" do
    before(:each) do
      @task = Task.make
      @attributes = @task.attributes
      @properties = @task.company.properties
      @task.set_property_value(@properties.first, @properties.first.property_values.first)
      @task.set_property_value(@properties[1], @properties[1].property_values.first)
      @task.save!
      @attributes[:properties]={
        @properties[0].id => @properties[0].property_values[1].id, #change value of first property
        @properties[1].id => "",   #second property is blank, so should be removed
        @properties[2].id => @properties[2].property_values[0].id # third property added
      }
      @task_property_values=@task.task_property_values
    end
    context "when attributes assigned" do
      before(:each) do
        @task.attributes= @attributes
      end

      it "should changed task_property_values with new values" do
        @task.attributes= @attributes
        @task.property_value(@properties[0]).should == @properties[0].property_values[1]
      end

      it "should not delete any task_property_values" do
        @task.property_value(@properties[1]).should_not be_nil
      end

      it "should build new task_property_values" do
        @task.property_value(@properties[2]).should == @properties[2].property_values[0]
      end
    end
    context "when task saved" do
      before(:each) do
        @task.attributes=@attributes
        @task.save!
        @task.reload
      end
      it "should changed task_property_values with new values" do
        @task.property_value(@properties[0]).should == @properties[0].property_values[1]
      end

      it "should delete task_property_values if value is blank" do
        @task.property_value(@properties[1]).should be_nil
      end
      it "should create new task_property_values" do
        @task.property_value(@properties[2]).should == @properties[2].property_values[0]
      end
    end
    context "when task not saved" do
      before(:each) do
        @attributes[:project_id]=""
        @task.attributes=@attributes
        @task.save.should == false
        @task.reload
      end
      it "should not change task_property_values in database" do
        @task.property_value(@properties[0]).should == @properties[0].property_values.first
        @task.property_value(@properties[1]).should == @properties[1].property_values.first
        @task.property_value(@properties[2]).should == nil
      end
    end
  end
  describe "add users, resources, dependencies to task using Task#set_users_resources_dependencies" do
    before(:each) do
      @company = Company.make
      @task = Task.make(:company=>@company)
      @user = User.make(:company=>@company, :projects=>[@task.project], :admin=>true)
      @resource = Resource.make(:company=>@company)
      @task.owners<< User.make(:company=>@company, :projects=>[@task.project])
      @task.watchers<< User.make(:company=>@company, :projects=>[@task.project])
      @task.resources<< Resource.make(:company=>@company)
      @task.dependencies<< Task.make(:company=>@company, :project=>@task.project)
      @params = {:dependencies=>[@task.dependencies.first.task_num.to_s],
                     :resource=>{:name=>'',:ids=>@task.resource_ids},
                     :assigned=>@task.owner_ids,
                     :users=>@task.user_ids}
      @task.save!
    end
    context "when task saved" do
      it "should saved new user in database if add task user" do
        @params[:users] << @user.id
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.users.should include(@user)
      end

      it "should saved task without user in database if delete task user" do
        @params[:users] = []
        @params[:assigned] = []
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.users.should == []
      end

      it "should saved new resource in database if add task resource" do
        @task.resource_ids.should_not include(@resource.id)
        @params[:resource][:ids] << @resource.id
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.resources.should include(@resource)
      end
      it "should saved task without resource in database if delete task resource" do
        @params[:resource][:ids] = []
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.resources.should == []
      end
      it "should saved new dependencies if add task dependencies" do
        dependent = Task.make(:company => @company, :project => @task.project)
        @params[:dependencies] << dependent.task_num.to_s
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.dependencies.should include(dependent)
      end
      it "should saved task without dependency if delete task dependencies" do
        @params[:dependencies]=[]
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.dependencies.should == []
      end

      it "should not change task user in database if not changed task user" do
        user_ids = @task.user_ids
        @params[:resource][:ids] << @resource.id
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.user_ids.should == user_ids
      end
      it "should not change task resource in database if not changed task resource" do
        resource_ids = @task.resource_ids
        @params[:users] << @user.id
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.resource_ids.should == resource_ids
      end
      it "should not change task dependency in database if not changed task dependency" do
        dependency_ids = @task.dependency_ids
        @params[:users] << @user.id
        @params[:resource][:ids] << @resource.id
        @task.set_users_dependencies_resources(@params, @user)
        @task.save.should == true
        @task.reload
        @task.dependency_ids.should == dependency_ids
      end
    end

    context "when task not saved" do

      it "should build new user in memory if add task user" do
        pending
        @params[:users] << @user.id
        @task.set_users_dependencies_resources(@params, @user)
        @task.project_id = nil
        @task.save.should == false
        @task.users.should include(@user)
        @task.reload
        @task.users.should_not include(@user)
      end

      it "should delete exist user from memory if delete task user" do
        pending
        @params[:user] = []
        @params[:assigned] = []
        @task.set_users_dependencies_resources(@params, @user)
        @task.project_id = nil
        @task.save.should == false
        @task.users.should == []
        @task.reload
        @task.users.should_not []
      end

      it "should build new resource in memory if add task resource" do
        pending
        @task.resource_ids.should_not include(@resource.id)
        @params[:resource][:ids] << @resource.id
        @task.set_users_dependencies_resources(@params, @user)
        @task.project_id = nil
        @task.save.should == false
        @task.resources.should include(@resource)
        @task.reload
        @task.resources.should_not include(@resource)
      end

      it "should delete exist resource from memory if delete task resource" do
        pending
        @task.resources.should_not be_empty
        ids= @task.resource_ids
        @params[:resource][:ids] = []
        @task.set_users_dependencies_resources(@params, @user)
        @task.project_id = nil
        @task.save.should == false
        @task.resources.should be_empty
        @task.reload
        @task.resource_ids.should == ids
      end

      it "should build new dependency in memory if add task dependency" do
        pending
        dependent = Task.make(:company => @company, :project => @task.project)
        @params[:dependencies] << dependent.task_num.to_s
        @task.set_users_dependencies_resources(@params, @user)
        @task.project_id = nil
        @task.save.should == false
        @task.dependencies.should include(dependent)
        @task.reload
        @task.dependencies.should_not include(dependent)
      end
      it "should delete exist dependency from memory if delete task dependency"

      it "should not change task user in database if not change task user"
      it "should not change task resource in database if not change task resource"
      it "should not change task dependency in database if not change task dependency"
    end
  end

end

  describe "When updating a task" do

    context "and the project the task belongs to has a score_rule" do

      before(:each) do
        @new_score = 250
        score_rule = ScoreRule.make(:score      => @new_score, 
                                    :score_type => ScoreRuleTypes::FIXED)

        project = Project.make(:score_rules => [score_rule])
        @task   = Task.make(:project => project)
      end

      it "should update its own score adjustment" do
        old_score = @task.weight_adjustment
        @task.name = 'bananas'
        @task.save
        @task.weight_adjustment.should == (old_score + @new_score)
      end
    end

    context "when the task is closed" do
      before(:each) do
        @task = Task.make(:status           => Task::CLOSED, 
                          :weight           => 100,
                          :weight_adjustment => 150)
      end

      it "should default its weight to zero" do
        @task.weight.should be_zero
      end

      it "should default its weight_adjustment to zero" do
        @task.weight_adjustment.should be_zero
      end
    end
  end
