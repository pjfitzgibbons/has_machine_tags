current_dir = File.dirname(__FILE__)
$:.unshift(current_dir) unless $:.include?(current_dir) || $:.include?(File.expand_path(current_dir))
require 'has_machine_tags/finder'
require 'has_machine_tags/tag_list'
require 'has_machine_tags/console'

module HasMachineTags
  def self.included(base) #:nodoc:
    base.extend(ClassMethods)
  end

  module ClassMethods
    # ==== Options:
    # [:console] When true, adds additional instance methods to use mainly in irb.
    # [:reverse_has_many] Defines a has_many :through from tags to the model using the plural of the model name.
    # [:quick_mode] When true, enables a quick mode to input machine tags with HasMachineTags::InstanceMethods.tag_list=(). See examples at HasMachineTags::TagList.new().
    def has_machine_tags(options={})
      cattr_accessor :quick_mode
      cattr_accessor :cached_tag_list_column_name
      
      self.quick_mode = options[:quick_mode] || false
      self.cached_tag_list_column_name = options[:cached_tag_list_column_name] || "cached_tag_list"
      self.class_eval do
        has_many :taggings, :as=>:taggable, :dependent=>:destroy
        has_many :tags, :through=>:taggings
        before_save :save_cached_tag_list
        after_save :save_tags

        include HasMachineTags::InstanceMethods
        extend HasMachineTags::Finder
        include HasMachineTags::Console::InstanceMethods if options[:console]

        if respond_to?(:named_scope)
          named_scope :tagged_with, lambda{ |*args|
            find_options_for_tagged_with(*args)
          }
        end
      end
      if options[:reverse_has_many]
        model = self.to_s
        'Tag'.constantize.class_eval do
          has_many(model.tableize, :through => :taggings, :source => :taggable, :source_type =>model)
        end
      end
    end

    def caching_tag_list?
      column_names.include?(self.cached_tag_list_column_name)
    end

  end

  module InstanceMethods
    # Set tag list with an array of tags or comma delimited string of tags.
    def tag_list=(list)
      @tag_list = current_tag_list(list)
    end

    def current_tag_list(list) #:nodoc:
      TagList.new(list, :quick_mode=>self.quick_mode)
    end

    # Fetches latest tag list for an object
    # def tag_list
    #   @tag_list ||= TagList.new(self.tags.map(&:name))
    # end

    def tag_list
      return @tag_list if @tag_list
      
      if cached_tag_value
        @tag_list = TagList.new(cached_tag_value)
      else
        @tag_list = TagList.new(self.tags.map(&:name))
      end
    end
    
    def cached_tag_value
        cached_value = send(self.class.cached_tag_list_column_name) if self.class.caching_tag_list?
    end

    def quick_mode_tag_list
      tag_list.to_quick_mode_string
    end

    protected
      def save_cached_tag_list
        if self.class.caching_tag_list?
          self[self.class.cached_tag_list_column_name] = tag_list.to_s
        end
      end

      # :stopdoc:
      def save_tags
        self.class.transaction do
          delete_unused_tags
          add_new_tags
        end
      end

      def delete_unused_tags
        unused_tags = tags.select {|e| !tag_list.include?(e.name) }
        tags.delete(*unused_tags)
      end

      def add_new_tags
        new_tags = tag_list - (self.tags || []).map(&:name)
        new_tags.each do |t|
          self.tags << Tag.find_or_initialize_by_name(t)
        end
      end
      #:startdoc:
  end

end
