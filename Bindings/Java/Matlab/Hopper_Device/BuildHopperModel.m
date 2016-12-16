% TODO license.

import org.opensim.modeling.*;

hopper = Model();
hopper.setName('Dennis')


%% Bodies and joints.
% -------------------
% Create the pelvis, thigh, and shank bodies.
pelvisMass = 30.0; pelvisHalfLength = 0.1;
pelvisInertia = Inertia(Vec3(pelvisMass * 2/3*pelvisHalfLength^2));
pelvis = Body('pelvis', pelvisMass, Vec3(0), pelvisInertia);

linkMass = 10.0; linkHalfLength = 0.25; linkRadius = 0.035;
linkIxx = linkMass * (linkRadius^2 / 4 + linkHalfLength^2 / 3);
linkInertia = Inertia(Vec3(linkIxx, linkMass * linkRadius^2 / 2, linkIxx));
thigh = Body('thigh', linkMass, Vec3(0), linkInertia);
shank = Body('shank', linkMass, Vec3(0), linkInertia);

% Add the bodies to the model (the model takes ownership).
hopper.addBody(pelvis);
hopper.addBody(thigh);
hopper.addBody(shank);

% Attach the pelvis to ground with a vertical slider joint, and attach the
% pelvis, thigh, and shank bodies to each other with pin joints.
sliderOrientation = Vec3(0, 0, pi/2);
sliderToGround = SliderJoint('slider', ...
        hopper.getGround(), Vec3(0), sliderOrientation, ...
        pelvis,             Vec3(0), sliderOrientation);
linkDistalPoint = Vec3(0, -linkHalfLength, 0);
linkProximalPoint = Vec3(0, linkHalfLength, 0);
% Define the pelvis as the parent so the reported value is hip flexion.
hip = PinJoint('hip', pelvis, Vec3(0),           Vec3(0), ...
                      thigh,  linkProximalPoint, Vec3(0));
% Define the shank as the parent so the reported value is knee flexion.
knee = PinJoint('knee', shank, linkProximalPoint, Vec3(0), ...
                        thigh, linkDistalPoint,   Vec3(0));

%/ Add the joints to the model.
hopper.addJoint(sliderToGround);
hopper.addJoint(hip);
hopper.addJoint(knee);

% Set the coordinate names and default values.
sliderCoord = sliderToGround.upd_coordinates(0);
sliderCoord.setName('yCoord');
sliderCoord.setDefaultValue(1.);

hipCoord = hip.upd_coordinates(0);
hipCoord.setName('hipFlexion');
hipCoord.setDefaultValue(0.35);

kneeCoord = knee.upd_coordinates(0);
kneeCoord.setName('kneeFlexion');
kneeCoord.setDefaultValue(0.75);


%% Passive force components.
% --------------------------
% Limit the range of motion for the hip and knee joints.
hipRange = [110., -90.];
hipStiff = [20., 20.]; hipDamping = 5.; hipTransition = 10.;
hipLimitForce = CoordinateLimitForce('hipFlexion', hipRange(1), ...
    hipStiff(1), hipRange(2), hipStiff(2), hipDamping, hipTransition);
hip.addComponent(hipLimitForce);

kneeRange = [140., 10.];
kneeStiff = [50., 40.]; kneeDamping = 2.; kneeTransition = 10.;
kneeLimitForce = CoordinateLimitForce('kneeFlexion', kneeRange(1), ...
    kneeStiff(1), kneeRange(2), kneeStiff(2), kneeDamping, kneeTransition);
knee.addComponent(kneeLimitForce);

% Create a constraint to keep the foot (distal end of the shank) directly
% beneath the pelvis (the Y-axis points upwards).
constraint = PointOnLineConstraint(hopper.getGround(), Vec3(0, 1 ,0), ...
        Vec3(0), shank, linkDistalPoint);
shank.addComponent(constraint);

% Use a contact model to prevent the foot (ContactSphere) from passing
% through the floor (ContactHalfSpace).
floor = ContactHalfSpace(Vec3(0), Vec3(0, 0, -pi/2), hopper.getGround(), ...
        'floor');
footRadius = 0.1;
foot = ContactSphere(footRadius, linkDistalPoint, shank, 'foot');

stiffness = 1.e8; dissipation = 0.5; friction = [0.9, 0.9, 0.6];
contactForce = HuntCrossleyForce();
contactForce.setStiffness(stiffness);
contactForce.setDissipation(dissipation);
contactForce.setStaticFriction(friction(1));
contactForce.setDynamicFriction(friction(2));
contactForce.setViscousFriction(friction(3));
contactForce.addGeometry('floor');
contactForce.addGeometry('foot');

% Add the contact-related components to the model.
hopper.addContactGeometry(floor);
hopper.addContactGeometry(foot);
hopper.addForce(contactForce);


%% Actuator.
% ----------
% Create the vastus muscle and set its origin and insertion points.
mclFmax = 4000.; mclOptFibLen = 0.55; mclTendonSlackLen = 0.25;
mclPennAng = 0.;
vastus = Thelen2003Muscle('vastus', mclFmax, mclOptFibLen, ...
        mclTendonSlackLen, mclPennAng);
vastus.addNewPathPoint('origin', thigh, Vec3(linkRadius, 0.1, 0));
vastus.addNewPathPoint('insertion', shank, Vec3(linkRadius, 0.15, 0));
hopper.addForce(vastus);

%/ Attach a cylinder (patella) to the distal end of the thigh over which the
%/ vastus muscle can wrap. 
patellaFrame = PhysicalOffsetFrame('patellaFrame', thigh, ...
        Transform(linkDistalPoint));
patella = WrapCylinder();
patella.setName('patella');
patella.set_radius(0.08);
patella.set_length(linkRadius*2.);
patella.set_quadrant('x');
patellaFrame.addWrapObject(patella);
thigh.addComponent(patellaFrame);
% Configure the vastus muscle to wrap over the patella.
vastus.updGeometryPath().addPathWrap(patella);


%% Controller.
% ------------
% Create a controller to excite the vastus muscle.
brain = PrescribedController();
brain.setActuators(hopper.updActuators());
controlFunction = PiecewiseConstantFunction();
controlFunction.addPoint(0.0, 0.3);
controlFunction.addPoint(2.0, 1.0);
controlFunction.addPoint(3.9, 0.1);
brain.prescribeControlForActuator('vastus', controlFunction);
hopper.addController(brain);


% Device attachment frames.
% -------------------------
% Create frames on the thigh and shank segments for attaching the device.
thighAttachment = PhysicalOffsetFrame('deviceAttachmentPoint', thigh, ...
        Transform(Vec3(linkRadius, 0.15, 0)));
shankAttachment = PhysicalOffsetFrame('deviceAttachmentPoint', shank, ...
        Transform(Vec3(linkRadius, 0, 0)));
thigh.addComponent(thighAttachment);
shank.addComponent(shankAttachment);


%% Display geometry.
% ------------------
% Attach geometry to the bodies and enable the visualizer.
pelvisGeometry = Brick(Vec3(pelvisHalfLength));
pelvisGeometry.setColor(Vec3(0.8, 0.1, 0.1));
pelvis.attachGeometry(pelvisGeometry);

linkGeometry = Cylinder(linkRadius, linkHalfLength);
linkGeometry.setColor(Vec3(0.8, 0.1, 0.1));
thigh.attachGeometry(linkGeometry);
shank.attachGeometry(linkGeometry.clone());

hopper.setUseVisualizer(true);

state = hopper.initSystem();
hopper.getVisualizer().show(state)

manager = Manager(hopper);
manager.setFinalTime(10.0);
manager.integrate(state);

hopper.print('Hopper.osim');
