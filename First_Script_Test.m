%% First_Script_Test
%% In the starting part of this file we create the set omega_r and omega_a (given from the paper proposed)
%% and, through the use of MatPower, we create a 39-bus system. Initially the system has all the transmission
%% lines settled to 1, so we have to recreate the environment created on the paper to test the algorithm.

clear
clc
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM,VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B,RATE_C, TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST,ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN,MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX,QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;

%% Nominal model initialization
model = case39();

%% Initialization of vector of digital measurements
z_digital = ones(1,46);

%% Set of removable lines for the nominal model. From these lines the attacker will choose the one that will be settled from CLOSE to OPEN

% omega_r_set = [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 19, 21, 22, ...
%                 23, 24, 25, 26, 29, 30, 31, 35, 36, 38, 40, 42, 43, 44, 45];
omega_r_set = [10,19, 12, 23, 3, 8, 6];
%omega_r_set = [23,9,14, 42];

%% Set oF not currently used lines, these will be added by the attacker by changing its status form OPEN to CLOSE 
omega_a_set = [18, 28];

%% Set the limit for state estimation during BDD

tau = 3000; %100;

%% The not currenly used lines must be OPEN in the nominal model
z_digital(omega_a_set) = 0;

%% The new model with the nominal topology is
model = utils().change_topology_model(model, z_digital);

%% STEP 1 --- ISO DECISION-MAKING BASED ON TOPOLOGY UNDER NO ATTACK

%This step consists in the solution of the sced model, as a sced model
%solution we used the OPF tool of matpower. The minimization function of
%OPF is described in [MATPOWER: Steady-State Operations,Planning and Analysis Tools for
%Power Systems Research and Education]. "The objective function (41) is simply a summation of individ-ual 
% polynomial cost functions f i P and f i Q of real and reactive
% power injections, respectively, for each generator"

%The first step is the solution of sced model, with OPF function of matlab
opf1_res = runopf(model);

%From the solution of this process we get the measurments. In this model we
%assumed the presence of only power meters, to take informazion about:

% - Active/Reactive power at "from" and "to" ends of each branch (46
% branche in the model)

% - Active/Reactive power generated by each generator (10 Gen bus)

%Get optimal generation power on nominal model
Pg = opf1_res.gen(:,PG);
Qg = opf1_res.gen(:,QG);

%Take power flow measures
% the measurement vector is
PFrom = opf1_res.branch(:,PF);
PTo = opf1_res.branch(:,PT);
QFrom = opf1_res.branch(:,QF);
QTo = opf1_res.branch(:,QT);

%The power for each branch must follow the relation                        
%|PF+PT+P(dissipated) = 0|
%This could be useful, since when a breaker is open or closed, the power
%flow at the two ends must be complaiant with theirself

%Get LMP
lmp = opf1_res.bus(:,LAM_P);

%Build measurment vector
z_measures = [PFrom; PTo; Pg; QFrom; QTo; Qg];

%% Adding noise 
%The available measures are expressed as z = [PFrom; QFrom; PTo; QTo; Pg; Qg; slack_Vm]
% Make the spread of the Gaussians be 20% of the a values
sigmas = 0.2 * z_measures; % Also a column vector.
% Create the noise values that we'll add to a.
randomNoise = randn(length(z_measures), 1) .* sigmas;
% Add noise to a to make an output column vector.
z_analog = z_measures + randomNoise;

%% STEP 2 - Initialization of NAA Algorithm

%% Parameters Initialization
popSize = 20;
generation = 20;

D = length(omega_r_set) + length(omega_a_set) + length(z_measures);

max_bound(1:length(z_measures)) = 100;
min_bound(1:length(z_measures)) = -100;

bounds = [zeros(1,length(omega_r_set)+length(omega_a_set)), min_bound;
          ones(1,length(omega_r_set)+length(omega_a_set)), max_bound];

types = [ones(1,length(omega_r_set)+length(omega_a_set)), zeros(1,length(z_measures))];

controlParam.shelterNum = 4;
avg = popSize/(controlParam.shelterNum);
controlParam.shelterCap = avg;
controlParam.scale_local = 1;
controlParam.Cr_local = 0.9;
controlParam.Cr_global = 0.1;
controlParam.alpha = 1.2;
controlParam.bounceBack = 0;

fitnessFuncName = 'utils().fitnessEval_Scenario1_Case1';
adjustIndFuncName = 'utils().constraintHandle';
global userObj;

%% Set User obj variables
userObj.tau = tau;
userObj.sigmas = sigmas;
userObj.nominal_model = model;
userObj.z_analog = z_analog;
userObj.z_digital = z_digital;
userObj.a_limit = 10;
userObj.omega_r_set = omega_r_set;
userObj.omega_a_set = omega_a_set;
userObj.Pg_star = Pg;
userObj.lmp_star = lmp;
userObj.PFrom_star = PFrom;

verbose = 1;

[bestFitness, bestInd, historicalFitness] = NAA(D, bounds, types, popSize, ...
    generation, adjustIndFuncName, fitnessFuncName, userObj, controlParam, verbose);



x = linspace(1, size(historicalFitness,2), 20);
y =  (historicalFitness.*(-1));


x = x(1, 1:length(x));
y = y(1, 1:length(y));

plot(x,y);
ylabel('Fitness value')
title('NAA Convergence')

%% Test Dragonfly Algorithm

% %Modify or replace Mycost.m according to your cost funciton
% CostFunction=@(x) utils().BDA_cost(x); 
% 
% %Maximum number of iterations
% Max_iteration=20;
% 
% %Number of particles
% N=10; 
% 
% %Number of variables
% nVar=length(omega_r_set) + length(omega_a_set);
% 
% %BDA with a v-shaped transfer function
% [Best_pos, Best_score ,Convergence_curve]=BDA(N, Max_iteration, nVar, CostFunction);
% 
% plot(Convergence_curve*-1,'DisplayName','BDA','Color', 'r');
% hold on
% 
% title('Convergence curve');
% xlabel('Iteration');ylabel('Average Best-so-far');
% 
% box on
% axis tight
% 
% display(['The best solution obtained by BDA is : ', num2str(Best_pos')]);
% display(['The best optimal value of the objective funciton found by BDA is : ', num2str(Best_score)]);

%% Test MOEAD/D 
% %Problem Definition
% %Cost Function
% CostFunction = @(x) utils().MOEAD_SCENARIO_2(x);  
% 
% % Number of Decision Variables
% nVar = length(omega_r_set) + length(omega_a_set); 
% 
% % Decision Variables Matrix Size
% VarSize = [nVar 1];  
% 
% % Decision Variables Lower Bound
% VarMin = 0;    
% % Decision Variables Upper Bound
% VarMax = 1;         
% nObj = numel(CostFunction(unifrnd(VarMin, VarMax, VarSize)));
% 
% [result,x] = moead(CostFunction, VarSize, VarMin, VarMax, nObj);

%% Test GA
% 
% CostFunction=@(x) utils().BDA_cost(x);
% nVar = length(omega_r_set) + length(omega_a_set);
% 
% X = ga(CostFunction, nVar);



