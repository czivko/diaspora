#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'spec_helper'

describe User do

  before do
    @alices_aspect = alice.aspects.where(:name => "generic").first
    @eves_aspect = eve.aspects.where(:name => "generic").first
    @bobs_aspect = bob.aspects.where(:name => "generic").first
  end

  describe "#visible_posts" do
    it "contains your public posts" do
      public_post = alice.post(:status_message, :text => "hi", :to => @alices_aspect.id, :public => true)
      alice.visible_posts.should include(public_post)
    end

    it "contains your non-public posts" do
      private_post = alice.post(:status_message, :text => "hi", :to => @alices_aspect.id, :public => false)
      alice.visible_posts.should include(private_post)
    end

    it "contains public posts from people you're following" do
      dogs = bob.aspects.create(:name => "dogs")
      bobs_public_post = bob.post(:status_message, :text => "hello", :public => true, :to => dogs.id)
      alice.visible_posts.should include(bobs_public_post)
    end

    it "contains non-public posts from people who are following you" do
      bobs_post = bob.post(:status_message, :text => "hello", :to => @bobs_aspect.id)
      alice.visible_posts.should include(bobs_post)
    end

    it "does not contain non-public posts from aspects you're not in" do
      dogs = bob.aspects.create(:name => "dogs")
      invisible_post = bob.post(:status_message, :text => "foobar", :to => dogs.id)
      alice.visible_posts.should_not include(invisible_post)
    end

    it "does not contain pending posts" do
      pending_post = bob.post(:status_message, :text => "hey", :public => true, :to => @bobs_aspect.id, :pending => true)
      pending_post.should be_pending
      alice.visible_posts.should_not include pending_post
    end

    it "does not contain pending photos" do
      pending_photo = bob.post(:photo, :pending => true, :user_file=> File.open(photo_fixture_name), :to => @bobs_aspect)
      alice.visible_posts.should_not include pending_photo
    end

    it "respects the :type option" do
      photo = bob.post(:photo, :pending => false, :user_file=> File.open(photo_fixture_name), :to => @bobs_aspect)
      alice.visible_posts.should include(photo)
      alice.visible_posts(:type => 'StatusMessage').should_not include(photo)
    end

    it "does not contain duplicate posts" do
      bobs_other_aspect = bob.aspects.create(:name => "cat people")
      bob.add_contact_to_aspect(bob.contact_for(alice.person), bobs_other_aspect)
      bob.aspects_with_person(alice.person).should =~ [@bobs_aspect, bobs_other_aspect]

      bobs_post = bob.post(:status_message, :text => "hai to all my people", :to => [@bobs_aspect.id, bobs_other_aspect.id])

      alice.visible_posts.length.should == 1
      alice.visible_posts.should include(bobs_post)
    end

    describe 'hidden posts' do
      before do
        aspect_to_post = bob.aspects.where(:name => "generic").first
        @status = bob.post(:status_message, :text=> "hello", :to => aspect_to_post)
        @vis = @status.post_visibilities.first
      end

      it "pulls back non hidden posts" do
        alice.visible_posts.include?(@status).should be_true
      end

      it "does not pull back hidden posts" do
        @vis.update_attributes(:hidden => true)
        alice.visible_posts.include?(@status).should be_false
      end
    end

    context 'with many posts' do
      before do
        bob.move_contact(eve.person, @bobs_aspect, bob.aspects.create(:name => 'new aspect'))
        time_interval = 1000
        time_past = 1000000
        (1..25).each do |n|
          [alice, bob, eve].each do |u|
            aspect_to_post = u.aspects.where(:name => "generic").first
            post = u.post :status_message, :text => "#{u.username} - #{n}", :to => aspect_to_post.id
            post.created_at = (post.created_at-time_past) - time_interval
            post.updated_at = (post.updated_at-time_past) + time_interval
            post.save
            time_interval += 1000
          end
        end
      end
      it 'works' do # The set up takes a looong time, so to save time we do several tests in one
        bob.visible_posts.length.should == 15 #it returns 15 by default
        bob.visible_posts.should == bob.visible_posts(:by_members_of => bob.aspects.map { |a| a.id }) # it is the same when joining through aspects
        bob.visible_posts.sort_by { |p| p.updated_at }.map { |p| p.id }.should == bob.visible_posts.map { |p| p.id }.reverse #it is sorted updated_at desc by default

        # It should respect the order option
        opts = {:order => 'created_at DESC'}
        bob.visible_posts(opts).first.created_at.should > bob.visible_posts(opts).last.created_at

        # It should respect the order option
        opts = {:order => 'updated_at DESC'}
        bob.visible_posts(opts).first.updated_at.should > bob.visible_posts(opts).last.updated_at
        
        # It should respect the limit option
        opts = {:limit => 40}
        bob.visible_posts(opts).length.should == 40
        bob.visible_posts(opts).should == bob.visible_posts(opts.merge(:by_members_of => bob.aspects.map { |a| a.id }))
        bob.visible_posts(opts).sort_by { |p| p.updated_at }.map { |p| p.id }.should == bob.visible_posts(opts).map { |p| p.id }.reverse

        # It should paginate using a datetime timestamp
        last_time_of_last_page = bob.visible_posts.last.updated_at
        opts = {:max_time => last_time_of_last_page}
        bob.visible_posts(opts).length.should == 15
        bob.visible_posts(opts).map { |p| p.id }.should == bob.visible_posts(opts.merge(:by_members_of => bob.aspects.map { |a| a.id })).map { |p| p.id }
        bob.visible_posts(opts).sort_by { |p| p.updated_at }.map { |p| p.id }.should == bob.visible_posts(opts).map { |p| p.id }.reverse
        bob.visible_posts(opts).map { |p| p.id }.should == bob.visible_posts(:limit => 40)[15...30].map { |p| p.id } #pagination should return the right posts

        # It should paginate using an integer timestamp
        opts = {:max_time => last_time_of_last_page.to_i}
        bob.visible_posts(opts).length.should == 15
        bob.visible_posts(opts).map { |p| p.id }.should == bob.visible_posts(opts.merge(:by_members_of => bob.aspects.map { |a| a.id })).map { |p| p.id }
        bob.visible_posts(opts).sort_by { |p| p.updated_at }.map { |p| p.id }.should == bob.visible_posts(opts).map { |p| p.id }.reverse
        bob.visible_posts(opts).map { |p| p.id }.should == bob.visible_posts(:limit => 40)[15...30].map { |p| p.id } #pagination should return the right posts
      end
    end
  end

  describe '#find_visible_post_by_id' do
    it "returns a post if you can see it" do
      bobs_post = bob.post(:status_message, :text => "hi", :to => @bobs_aspect.id, :public => false)
      alice.find_visible_post_by_id(bobs_post.id).should == bobs_post
    end
    it "returns nil if you can't see that post" do
      dogs = bob.aspects.create(:name => "dogs")
      invisible_post = bob.post(:status_message, :text => "foobar", :to => dogs.id)
      alice.find_visible_post_by_id(invisible_post.id).should be_nil
    end
  end

  context 'with two users' do
    describe '#people_in_aspects' do
      it 'returns people objects for a users contact in each aspect' do
        alice.people_in_aspects([@alices_aspect]).should == [bob.person]
      end

      it 'returns local/remote people objects for a users contact in each aspect' do
        local_user1 = Factory(:user)
        local_user2 = Factory(:user)
        remote_user = Factory(:user)

        asp1 = local_user1.aspects.create(:name => "lol")
        asp2 = local_user2.aspects.create(:name => "brb")
        asp3 = remote_user.aspects.create(:name => "ttyl")

        connect_users(alice, @alices_aspect, local_user1, asp1)
        connect_users(alice, @alices_aspect, local_user2, asp2)
        connect_users(alice, @alices_aspect, remote_user, asp3)

        local_person = remote_user.person
        local_person.owner_id = nil
        local_person.save
        local_person.reload

        alice.people_in_aspects([@alices_aspect]).count.should == 4
        alice.people_in_aspects([@alices_aspect], :type => 'remote').count.should == 1
        alice.people_in_aspects([@alices_aspect], :type => 'local').count.should == 3
      end

      it 'does not return people not connected to user on same pod' do
        3.times { Factory(:user) }
        alice.people_in_aspects([@alices_aspect]).count.should == 1
      end

      it "only returns non-pending contacts" do
        alice.people_in_aspects([@alices_aspect]).should == [bob.person]
      end

      it "returns an empty array when passed an aspect the user doesn't own" do
        alice.people_in_aspects([@eves_aspect]).should == []
      end
    end
  end

  context 'contact querying' do
    let(:person_one) { Factory.create :person }
    let(:person_two) { Factory.create :person }
    let(:person_three) { Factory.create :person }
    let(:aspect) { alice.aspects.create(:name => 'heroes') }

    describe '#contact_for_person_id' do
      it 'returns a contact' do
        contact = Contact.create(:user => alice, :person => person_one, :aspects => [aspect])
        alice.contacts << contact
        alice.contact_for_person_id(person_one.id).should be_true
      end

      it 'returns the correct contact' do
        contact = Contact.create(:user => alice, :person => person_one, :aspects => [aspect])
        alice.contacts << contact

        contact2 = Contact.create(:user => alice, :person => person_two, :aspects => [aspect])
        alice.contacts << contact2

        contact3 = Contact.create(:user => alice, :person => person_three, :aspects => [aspect])
        alice.contacts << contact3

        alice.contact_for_person_id(person_two.id).person.should == person_two
      end

      it 'returns nil for a non-contact' do
        alice.contact_for_person_id(person_one.id).should be_nil
      end

      it 'returns nil when someone else has contact with the target' do
        contact = Contact.create(:user => alice, :person => person_one, :aspects => [aspect])
        alice.contacts << contact
        eve.contact_for_person_id(person_one.id).should be_nil
      end
    end

    describe '#contact_for' do
      it 'takes a person_id and returns a contact' do
        alice.should_receive(:contact_for_person_id).with(person_one.id)
        alice.contact_for(person_one)
      end

      it 'returns nil if the input is nil' do
        alice.contact_for(nil).should be_nil
      end
    end

    describe '#aspects_with_person' do
      before do
        @connected_person = bob.person
      end

      it 'should return the aspects with given contact' do
        alice.aspects_with_person(@connected_person).should == [@alices_aspect]
      end

      it 'returns multiple aspects if the person is there' do
        aspect2 = alice.aspects.create(:name => 'second')
        contact = alice.contact_for(@connected_person)

        alice.add_contact_to_aspect(contact, aspect2)
        alice.aspects_with_person(@connected_person).to_set.should == alice.aspects.to_set
      end
    end
  end

  describe '#posts_from' do
    before do
      @user3 = Factory(:user)
      @aspect3 = @user3.aspects.create(:name => "bros")

      @public_message = @user3.post(:status_message, :text => "hey there", :to => 'all', :public => true)
      @private_message = @user3.post(:status_message, :text => "hey there", :to => @aspect3.id)
    end

    it 'displays public posts for a non-contact' do
      alice.posts_from(@user3.person).should include @public_message
    end

    it 'does not display private posts for a non-contact' do
      alice.posts_from(@user3.person).should_not include @private_message
    end

    it 'displays private and public posts for a non-contact after connecting' do
      connect_users(alice, @alices_aspect, @user3, @aspect3)
      new_message = @user3.post(:status_message, :text=> "hey there", :to => @aspect3.id)

      alice.reload

      alice.posts_from(@user3.person).should include @public_message
      alice.posts_from(@user3.person).should include new_message
    end

    it 'displays recent posts first' do
      msg3 = @user3.post(:status_message, :text => "hey there", :to => 'all', :public => true)
      msg4 = @user3.post(:status_message, :text => "hey there", :to => 'all', :public => true)
      msg3.created_at = Time.now+10
      msg3.save!
      msg4.created_at = Time.now+14
      msg4.save!

      alice.posts_from(@user3.person).map { |p| p.id }.should == [msg4, msg3, @public_message].map { |p| p.id }
    end
  end
end
