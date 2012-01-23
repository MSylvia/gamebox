# this module gets mixed into a stage to allow it to handle collision detection
module AABBArbiter
  attr_reader :checks, :collisions

  def register_collidable(actor)
    stagehand(:spatial_tree).add(actor)
  end

  def unregister_collidable(actor)
    stagehand(:spatial_tree).remove(actor)
  end

  def on_collision_of(first_objs, second_objs, &block)
    first_objs = [first_objs].flatten
    second_objs = [second_objs].flatten

    @collision_handlers ||= {}

    first_objs.each do |fobj|
      second_objs.each do |sobj|
        if fobj < sobj
          @collision_handlers[fobj] ||= {}
          @collision_handlers[fobj][sobj] = [false,block]
        else
          @collision_handlers[sobj] ||= {}
          @collision_handlers[sobj][fobj] = [true,block]
        end
      end
    end
  end

  def interested_in_collision_of?(type1, type2)
    @collision_handlers ||= {}
    (@collision_handlers[type1] && @collision_handlers[type1][type2]) ||
    (@collision_handlers[type2] && @collision_handlers[type2][type1])
  end

  def run_callbacks(collisions)
    @collision_handlers ||= {}
    collisions.each do |collision|
      first = collision.first
      second = collision.last
      unless first.actor_type < second.actor_type
        tmp = first
        first = second
        second = tmp
      end

      colliders = @collision_handlers[first.actor_type]
      swapped, callback = colliders[second.actor_type] unless colliders.nil?
      unless callback.nil?
        if swapped
          callback.call second, first 
        else
          callback.call first, second 
        end
      end
    end
  end

  def find_collisions
    aabb_tree = stagehand(:spatial_tree)
    collidable_actors = aabb_tree.moved_items.values

    collisions = {}

    # aabb_tree.each do |actor|
    #   puts "#{actor.class} #{actor.bb}"
    # end
    puts "#"*80
    puts aabb_tree.instance_variable_get('@tree')
    collidable_actors.each do |first|
      if first.is? :collidable
        # TODO better method name (or return an Enumerator)
        aabb_tree.neighbors_of(first) do |second|
          puts "FOUND neighbors_of #{first.class}, #{second.class}" unless first == second
          if second.is? :collidable
            if first != second && 
              interested_in_collision_of?(first.actor_type, second.actor_type) &&
              collide?(first, second)
              collisions[second] ||= []
              if !collisions[second].include?(first)
                collisions[first] ||= []
                collisions[first] << second
              end
            end
          end
        end
      end
    end
    unique_collisions = []
    collisions.each do |first,seconds|
      seconds.each do |second|
        unique_collisions << [first,second]
      end
    end
    puts "found #{unique_collisions.size} uniqs" if unique_collisions.size > 0
    run_callbacks unique_collisions
    aabb_tree.reset
  end

  def collide?(object, other)
    if !other.is? :collidable
      binding.pry
    end
    case object.collidable_shape
    when :circle
      case other.collidable_shape
      when :circle
        collide_circle_circle? object, other
      when :aabb
        collide_circle_aabb? object, other
      when :polygon
        collide_circle_polygon? object, other
      end
    when :aabb
      case other.collidable_shape
      when :circle
        collide_aabb_circle? object, other
      when :aabb
        collide_aabb_aabb? object, other
      when :polygon
        collide_aabb_polygon? object, other
      end
    when :polygon
      case other.collidable_shape
      when :circle
        collide_polygon_circle? object, other
      when :aabb
        collide_polygon_aabb? object, other
      when :polygon
        collide_polygon_polygon? object, other
      end
    end
  end

  def collide_circle_circle?(object, other)
    x_delta = other.center_x - object.center_x
    x_dist  = x_delta * x_delta
    y_delta = other.center_y - object.center_y
    y_dist  = y_delta * y_delta

    total_radius = object.radius + other.radius
    (x_dist + y_dist) <= (total_radius * total_radius)
  end

  # Idea from:
  # http://gpwiki.org/index.php/Polygon_Collision
  # and http://www.gamedev.net/community/forums/topic.asp?topic_id=540755&whichpage=1&#3488866
  def collide_polygon_polygon?(object, other)
    if collide_circle_circle? object, other
      # collect vector's perp
      potential_sep_axis = 
        (object.cw_world_edge_normals | other.cw_world_edge_normals).uniq
      potential_sep_axis.each do |axis|
        return false unless project_and_detect(axis, object, other)
      end 
    else
      return false
    end
    true
  end
  alias collide_aabb_aabb? collide_polygon_polygon?

  # returns true if the projections overlap
  def project_and_detect(axis, a, b)
    a_min, a_max = send("#{a.collidable_shape}_interval", axis, a)
    b_min, b_max = send("#{b.collidable_shape}_interval", axis, b)

    a_min <= b_max && b_min <= a_max
  end

  def polygon_interval(axis, object)
    min = max = nil
    object.cw_world_points.each do |edge|
      # vector dot product
      d = edge[0] * axis[0] + edge[1] * axis[1]
      min ||= d
      max ||= d
      min = d if d < min
      max = d if d > max
    end
    [min,max]
  end
  alias aabb_interval polygon_interval

  def circle_interval(axis, object)
    axis_x = axis[0]
    axis_y = axis[1]

    obj_x = object.center_x
    obj_y = object.center_y

    length = Math.sqrt(axis_x * axis_x + axis_y * axis_y)
    cn = axis_x*obj_x + axis_y*obj_y
    rlength = object.radius*length
    min = cn - rlength
    max = cn + rlength
    [min,max]
  end

  def collide_polygon_circle?(object, other)
    collide_circle_polygon?(other, object)
  end
  alias collide_aabb_circle?  collide_polygon_circle?

  def collide_circle_polygon?(object, other)
    if collide_circle_circle? object, other
      potential_sep_axis = other.cw_world_edge_normals
      potential_sep_axis.each do |axis|
        return false unless project_and_detect(axis, object, other)           
      end 
      true 
    else
      false
    end
  end
  alias collide_circle_aabb? collide_circle_polygon?
end