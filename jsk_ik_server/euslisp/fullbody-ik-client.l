#!/usr/bin/env roseus

(ros::load-ros-manifest "hrpsys_gazebo_atlas")
(ros::load-ros-manifest "moveit_msgs")
(ros::roseus "fullbody_ik_client_test")

(require :hrp2jsknt "package://hrpsys_ros_bridge_tutorials/models/hrp2jsknt.l")
(defvar *robot* (hrp2jsknt))
(objects *robot*)

(defun coords2posestamped
  (coords
   &key
   (frame_id "/pelvis")
   (origin
    (copy-object
     (send (car (send *robot* :links)) :worldcoords)))
   (coords-from-origin
    (send origin :transformation coords))
   (q (matrix2quaternion (send coords-from-origin :worldrot))))
  (instance
   geometry_msgs::PoseStamped
   :init
   :header (instance std_msgs::Header :init
		     :stamp (ros::time 0.0)
		     :frame_id "/pelvis")
   :pose
   (instance geometry_msgs::Pose
	     :init
	     :position
	     (instance geometry_msgs::Point :init
		       :x (aref (send coords-from-origin :worldpos) 0)
		       :y (aref (send coords-from-origin :worldpos) 1)
		       :z (aref (send coords-from-origin :worldpos) 2))
	     :orientation
	     (instance geometry_msgs::Quaternion :init
		       :x (elt q 1)
		       :y (elt q 2)
		       :z (elt q 3)
		       :w (elt q 0))
	     )))

(defun ik-server-call
  (&rest
   args
   &key
   (target-limb '(:rarm :larm :rleg :lleg))
   (move-target (mapcar #'(lambda (k) (send *robot* k :end-coords)) target-limb))
   (target-coords (send-all move-target :copy-worldcoords))
   ll
   collision-pair
   &allow-other-keys)
  (let* ((req (instance moveit_msgs::GetPositionIKRequest :init))
	 pc pc-list oc oc-list tf q res
	 (opt (list :worldcoords
		    (list 'make-coords
			  :pos (send (car (send *robot* :links)) :worldpos)
			  :rot (send (car (send *robot* :links)) :worldrot)))))
    ;; options
    (while (not (null args))
      (if (or (numberp (cadr args))
	      (vectorp (cadr args))
	      (and (listp (cadr args))
		   (find-if #'numberp (cadr args))))
	  (setq opt (append (list (car args) (cadr args)) opt)))
      (setq args (cddr args)))
    ;; group_name
    (send req :ik_request :group_name
	  (format nil ":fullbody-inverse-kinematics ~A" opt))
    ;; joint state
    (send req :ik_request :robot_state :joint_state
	  (instance sensor_msgs::JointState
		    :init
		    :header
		    (instance std_msgs::Header :init
			      :stamp (ros::time 0.0)
			      :frame_id "/pelvis")
		    :name
		    (mapcar #'(lambda (j) (format nil "~A" (send j :name)))
			    (send *robot* :joint-list))
		    :position
		    (map float-vector #'deg2rad
			 (send-all (send *robot* :joint-list) :joint-angle))))
    ;; move-target
    (dolist (mt move-target)
      (setq pc (instance moveit_msgs::PositionConstraint :init))
      (send pc :link_name
	    (format nil "~A" (send (send mt :parent) :name)))
      (setq tf
	    (send
	     (copy-object (send (send mt :parent) :worldcoords))
	     :transformation
	     (send mt :copy-worldcoords)))
      (send pc :target_point_offset
	    (instance geometry_msgs::vector3
		      :init
		      :x (aref (send tf :worldpos) 0)
		      :y (aref (send tf :worldpos) 1)
		      :z (aref (send tf :worldpos) 2)))
      (push pc pc-list)
      ;;
      (setq oc (instance moveit_msgs::OrientationConstraint :init))
      (send oc :link_name
	    (format nil "~A" (send (send mt :parent) :name)))
      (setq q (matrix2quaternion (send tf :worldrot)))
      (send oc :orientation
	    (instance geometry_msgs::Quaternion
		      :init
		      :w (aref q 0)
		      :x (aref q 1)
		      :y (aref q 2)
		      :z (aref q 3)))
      (push oc oc-list))
    (send req :ik_request :constraints :position_constraints pc-list)
    (send req :ik_request :constraints :orientation_constraints oc-list)
    ;;
    (send req :ik_request :ik_link_names
	  (mapcar #'(lambda (mt)
		      (format nil "~A" (send (send mt :parent) :name)))
		  move-target))
    ;;
    (send req :ik_request :pose_stamped_vector
	  (mapcar
	   #'coords2posestamped
	   target-coords))
    ;;req))
    (setq res (ros::service-call "/solve_ik" req))
    (cond
     ((= (send res :error_code :val) moveit_msgs::MoveItErrorCodes::*SUCCESS*)
      (ros::ros-info " success ~A"  (send res :solution :joint_state :position)))
     (t (ros::ros-error " failed ")))
    res))

(defun test-fullbody-ik
  (&key
   (target-limb '(:rarm :larm :rleg :lleg))
   (move-target (mapcar #'(lambda (k) (send *robot* k :end-coords)) target-limb))
   (target-coords (send-all move-target :copy-worldcoords)))
  (mapcar
   #'(lambda (tc)
       (send tc :transform
	     (make-coords
	      :pos (scale 300 (random-vector 1.0))
	      :rpy (scale 1.57 (random-vector 1.0)))))
   (subseq target-coords 0 2))
  (ik-server-call
   :target-limb target-coords
   :move-target move-target
   :target-coords target-coords
   :root-link-virtual-joint-weight #F(1 1 1 1 1 1)
   :centroid-thre 100
   ))

(do-until-key (test-fullbody-ik))