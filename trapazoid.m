function soln = trapazoid(problem)
% soln = trapazoid(problem)
%
% This function transcribes a trajectory optimization problem using the
% trapazoid method for enforcing the dynamics. It can be found in chapter
% four of Bett's book:
%
%   John T. Betts, 2001
%   Practical Methods for Optimal Control Using Nonlinear Programming
%
% For details on the input and output, see the help file for trajOpt.m
%

%To make code more readable
G = problem.guess;
B = problem.bounds;
F = problem.func;
nGrid = problem.options.nGrid;  %Number of grid points for transcription

% Interpolate the guess at the grid-points for transcription:
guess.tSpan = G.time([1,end]);
guess.time = linspace(guess.tSpan(1), guess.tSpan(2), nGrid);
guess.state = interp1(G.time', G.state', guess.time')';
guess.control = interp1(G.time', G.control', guess.time')';

[zGuess, pack] = packDecVar(guess.time, guess.state, guess.control);

%%%% Compute bounds on decision variables:

tLow = linspace(B.initialTime.low, B.finalTime.low, nGrid);
xLow = [B.initialState.low, B.state.low*ones(1,nGrid-2), B.finalState.low];
uLow = B.control.low*ones(1,nGrid);
zLow = packDecVar(tLow,xLow,uLow);

tUpp = linspace(B.initialTime.upp, B.finalTime.upp, nGrid);
xUpp = [B.initialState.upp, B.state.upp*ones(1,nGrid-2), B.finalState.upp];
uUpp = B.control.upp*ones(1,nGrid);
zUpp = packDecVar(tUpp,xUpp,uUpp);

%%%% Set up problem for fmincon:

P.objective = @(z)( ...
    myObjective(z, pack, F.pathObj, F.bndObj) );

P.nonlcon = @(z)( ...
    myConstraint(z, pack, F.dynamics, F.pathCst, F.bndCst) );

P.x0 = zGuess;
P.lb = zLow;
P.ub = zUpp;
P.Aineq = []; P.bineq = [];
P.Aeq = []; P.beq = [];
P.options = problem.nlpOpt;
P.solver = 'fmincon';

%%%% Call fmincon to solve the non-linear program (NLP)
tic;
[zSoln, objVal,exitFlag,output] = fmincon(P);
[tSoln,xSoln,uSoln] = unPackDecVar(zSoln,pack);
nlpTime = toc;

soln.grid.time = tSoln;
soln.grid.state = xSoln;
soln.grid.control = uSoln;

soln.info = output;
soln.info.nlpTime = nlpTime;
soln.info.exitFlag = exitFlag;
soln.info.objVal = objVal;

end


%%%%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~%%%%
%%%% SUB FUNCTIONS %%%%
%%%%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~%%%%


function [z,pack] = packDecVar(t,x,u)
%
% This function collapses the time (t), state (x)
% and control (u) matricies into a single vector
%
% INPUTS:
%   t = [1, nTime] = time vector (grid points)
%   x = [nState, nTime] = state vector at each grid point
%   u = [nControl, nTime] = control vector at each grid point
%
% OUTPUTS:
%   z = column vector of 2 + nTime*(nState+nControl) decision variables
%   pack = details about how to convert z back into t,x, and u
%       .nTime
%       .nState
%       .nControl
%

nTime = length(t);
nState = size(x,1);
nControl = size(u,1);

tSpan = [t(1); t(end)];
xCol = reshape(x, nState*nTime, 1);
uCol = reshape(u, nControl*nTime, 1);

z = [tSpan;xCol;uCol];

pack.nTime = nTime;
pack.nState = nState;
pack.nControl = nControl;

end

%%%%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~%%%%

function [t,x,u] = unPackDecVar(z,pack)
%
% This function unpacks the decision variables for
% trajectory optimization into the time (t),
% state (x), and control (u) matricies
%
% INPUTS:
%   z = column vector of 2 + nTime*(nState+nControl) decision variables
%   pack = details about how to convert z back into t,x, and u
%       .nTime
%       .nState
%       .nControl
%
% OUTPUTS:
%   t = [1, nTime] = time vector (grid points)
%   x = [nState, nTime] = state vector at each grid point
%   u = [nControl, nTime] = control vector at each grid point
%

nTime = pack.nTime;
nState = pack.nState;
nControl = pack.nControl;
nx = nState*nTime;
nu = nControl*nTime;

t = linspace(z(1),z(2),nTime);

x = reshape(z((2+1):(2+nx)),nState,nTime);
u = reshape(z((2+nx+1):(2+nx+nu)),nControl,nTime);

end

%%%%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~%%%%

function cost = myObjective(z,pack,pathObj,bndObj)
%
% This function unpacks the decision variables, sends them to the
% user-defined objective functions, and then returns the final cost
%
% INPUTS:
%   z = column vector of decision variables
%   pack = details about how to convert decision variables into t,x, and u
%   pathObj = user-defined integral objective function
%   endObj = user-defined end-point objective function
%
% OUTPUTS:
%   cost = scale cost for this set of decision variables
%

[t,x,u] = unPackDecVar(z,pack);

% Compute the cost integral along trajectory
if isempty(pathObj)
    integralCost = 0;
else
    dt = (t(end)-t(1))/(pack.nTime-1);
    integrand = pathObj(t,x,u);  %Calculate the integrand of the cost function
    integralCost = dt*trapz(integrand);  %Trapazoidal integration
end

% Compute the cost at the boundaries of the trajectory
if isempty(bndObj)
    bndCost = 0;
else
    t0 = t(1);
    tF = t(end);
    x0 = x(:,1);
    xF = x(:,end);
    bndCost = bndObj(t0,x0,tF,xF);
end

cost = bndCost + integralCost;

end

%%%%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~%%%%

function [c, ceq] = myConstraint(z,pack,dynFun, pathCst, bndCst)
%
% This function unpacks the decision variables, computes the defects along
% the trajectory, and then evaluates the user-defined constraint functions.
%
% INPUTS:
%   z = column vector of decision variables
%   pack = details about how to convert decision variables into t,x, and u
%   dynFun = user-defined dynamics function
%   pathCst = user-defined constraints along the path
%   endCst = user-defined constraints at the boundaries
%
% OUTPUTS:
%   c = inequality constraints to be passed to fmincon
%   ceq = equality constraints to be passed to fmincon
%

[t,x,u] = unPackDecVar(z,pack);

%%%% Compute defects along the trajectory:

dt = (t(end)-t(1))/(pack.nTime-1);
dx = dynFun(t,x,u);

xLow = x(:,1:end-1);
xUpp = x(:,2:end);

dxLow = dx(:,1:end-1);
dxUpp = dx(:,2:end);

% This is the key line:  (Trapazoid Rule)
defects = xUpp-xLow - 0.5*dt*(dxLow+dxUpp);
ceq_dyn = reshape(defects,numel(defects),1);

%%%% Compute the user-defined constraints:
if isempty(pathCst)
    c_path = [];
    ceq_path = [];
else
    [c_path, ceq_path] = pathCst(t,x,u);
end
if isempty(bndCst)
    c_bnd = [];
    ceq_bnd = [];
else
    [c_bnd, ceq_bnd] = bndCst(t,x,u);
end

%%%% Pack everything up:
c = [c_path;c_bnd];
ceq = [ceq_dyn; ceq_path; ceq_bnd];

end