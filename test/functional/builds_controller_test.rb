require 'test_helper'

class BuildsControllerTest < ActionController::TestCase
  include FileSandbox
  include BuildFactory

  context "GET /builds/:project" do
    test "should render that project's last build if no build is given" do
      with_sandbox_project do |sandbox, project|
        create_builds 24, 25

        Project.expects(:find).returns(project)

        get :show, :project => project.name

        assert_response :success
        assert_template 'show'
        assert_equal project, assigns(:project)
        assert_equal '25', assigns(:build).label
      end
    end

    test "should render successfully even if that project has no builds yet" do
      with_sandbox_project do |sandbox, project|
        Project.expects(:find).with(project.name).returns(project)

        get :show, :project => project.name

        assert_response :success
        assert_template 'no_builds_yet'
        assert_equal project, assigns(:project)
        assert_nil assigns(:build)
      end
    end

    test "GET /builds/:project should render a 404 and an error page of the requested project does not exist" do
      Project.expects(:find).with('foo').returns(nil)
      get :show, :project => 'foo'

      assert_response 404
      assert_equal 'Project "foo" not found', @response.body
    end

    test "should include a link to the project's RSS feed" do
      with_sandbox_project do |sandbox, project|
        sandbox.new :file => 'build-1/build_status.pingpong'
      
        Project.expects(:find).with(project.name).returns(project)
        get :show, :project => project.name
        assert_select "link[title='#{project.name} builds'][href=?]", project_path(project, :format => "rss")
      end    
    end
  end

  context "GET /builds/:project/:id" do
    test "should render the show template with the requested project and build" do
      with_sandbox_project do |sandbox, project|
        create_builds 23, 24, 25

        Project.expects(:find).with(project.name).returns(project)

        get :show, :project => project.name, :build => "24"

        assert_response :success
        assert_template 'show'
        assert_equal project, assigns(:project)
        assert_equal '24', assigns(:build).label
        
        assert_select "#navigate_build a[href=#{build_path(project.name, 25)}]", "next &gt;"
        assert_select "#navigate_build a[href=#{build_path(project.name, 23)}]", "&lt; prev"
        assert_select "#navigate_build a[href=#{project_without_builds_path(project.name)}]", "latest &gt;&gt;"
      end
    end

    test "should show a list of recent projects and a dropdown list of older projects" do
      begin
        old_history_limit = Configuration.build_history_limit
        Configuration.build_history_limit = 2

        with_sandbox_project do |sandbox, project|
          create_builds 1, 2, 3
          b1, b2, b3 = project.builds.reverse

          Project.stubs(:find).with(project.name).returns(project)

          get :show, :project => project.name, :id => "1"

          assert_select "div.build_link" do
            assert_select "a[href=?]", build_path(project, b1)
            assert_select "a[href=?]", build_path(project, b2)
            assert_select "a[href=?]", build_path(project, b3), false
          end

          assert_select "select#build" do
            assert_select "option", "Older Builds..."
            assert_select "option[value=?]", build_path(project, b3)
            assert_select "option[value=?]", build_path(project, b2), false
            assert_select "option[value=?]", build_path(project, b1), false
          end
        end
      ensure
        Configuration.build_history_limit = old_history_limit
      end
    end

    test "should render a 404 and an error page if the requested build does not exist" do
      with_sandbox_project do |sandbox, project|
        create_build 1
        Project.expects(:find).with(project.name).returns(project)

        get :show, :project => project.name, :build => "2"

        assert_response 404
        assert_equal 'Build "2" not found', @response.body
      end
    end
  end

  context "GET /:builds/:project/:id/artifact/*:path" do
    test "should render the requested file if it exists" do
      with_sandbox_project do |sandbox, project|
        create_build 1
        sandbox.new :file => 'build-1/rcov/index.html', :with_contents => 'apple pie'

        Project.expects(:find).with(project.name).returns(project)

        get :artifact, :project => project.name, :build => '1', :path => ['rcov', 'index.html']

        assert_response :success
        assert_equal 'apple pie', @response.body
        assert_equal 'text/html', @response.headers['Content-Type']
      end
    end
  
    [ 
      [ 'foo.jpg',  'image/jpeg'      ],
      [ 'foo.jpeg', 'image/jpeg'      ],
      [ 'foo.png',  'image/png'       ],
      [ 'foo.gif',  'image/gif'       ],
      [ 'foo.html', 'text/html'       ],
      [ 'foo.css',  'text/css'        ],
      [ 'foo.js',   'text/javascript' ],
      [ 'foo.txt',  'text/plain'      ],
      [ 'foo',      'text/plain'      ],
      [ 'foo.asdf', 'text/plain'      ]
    ].each do |file, type|
      test "should render #{file} with a content type of #{type}" do
        with_sandbox_project do |sandbox, project|
          create_build 1

          sandbox.new :file => "build-1/#{file}", :with_content => "lemon.#{file}"

          Project.expects(:find).with(project.name).returns(project)

          get :artifact, :project => project.name, :build => '1', :path => file

          assert_response :success
          assert_equal "lemon.#{file}", response.body
          assert_equal type, response.headers['Content-Type']
        end
      end
    end

    test "should render a 404 if the file does not exist" do
      with_sandbox_project do |sandbox, project|
        create_build 1

        Project.expects(:find).with(project.name).returns(project)

        get :artifact, :project => project.name, :build => '1', :path => 'foo'
        assert_response 404
      end
    end

    test "should render files in subdirectories of the main artifact directory" do
      with_sandbox_project do |sandbox, project|
        create_build 1
        sandbox.new :file => 'build-1/foo/index.html'

        Project.expects(:find).with(project.name).returns(project)

        get :artifact, :project => project.name, :build => '1', :path => 'foo'

        assert_redirected_to 'http://test.host/builds/my_project/1/foo/index.html'
      end
    end

    test "should render a 404 if the requested project does not exist" do
      Project.expects(:find).with('foo').returns(nil)

      get :artifact, :project => 'foo', :build => '1', :path => 'foo'
      assert_response 404
      assert_equal 'Project "foo" not found', @response.body
    end

    test "should render a 404 if the requested build does not exist" do
      mock_project = Object.new
      Project.expects(:find).with('foo').returns(mock_project)
      mock_project.expects(:find_build).with('1').returns(nil)

      get :artifact, :project => 'foo', :build => '1', :path => 'foo'
      assert_response 404
      assert_equal 'Build "1" not found', @response.body
    end

    test "should auto-refresh incomplete builds" do
      with_sandbox_project do |sandbox, project|
        sandbox.new :directory => 'build-1-success'
        sandbox.new :directory => 'build-2'
      
        Project.stubs(:find).with(project.name).returns(project)

        assert project.last_build.incomplete?
        
        get :show, :project => project.name, :build => '1'
        assert !assigns(:autorefresh)
        
        get :show, :project => project.name, :build => '2'
        assert assigns(:autorefresh)
      end
    end
  end
end