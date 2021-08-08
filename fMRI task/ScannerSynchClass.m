% Changes by TEC:
% Modified to work with 7T scanner
% Modified to set a maximum time to wait for button press
%
%Interface for National Instruments PCI 6503 card
%
% DESCRIPTION
%
% Properties (internal variables):
% 	IsValid						= device set and operational
% 	TR 							= set a non-zero value (in second) for	emulation mode (will also detect "real" pulse if present)
%
% 	Clock						= interal clock (seconds past since the first scanner pulse or clock reset)
% 	Synch						= current state of the scanner synch pulse
% 	TimeOfLastPulse				= time (according to the internal clock) of the last pulse
% 	SynchCount					= number of scanner synch pulses detected
%
% 	Buttons						= current state of the any button
% 	LastButtonPress				= index/indices of the last button(s) pressed
% 	TimeOfLastButtonPress		= time (according to the internal clock) of the last button press (any)
%
% Methods (internal functions):
% 	ScannerSynchClass			= constructor
% 	delete						= destructor
%	ResetClock					= reset internal clock
%
% 	ResetSynchCount				= reset scanner synch pulse counter
%	SetSynchReadoutTime(t)		= blocks scanner synch pulse readout after a pulse for 't' seconds
%	WaitForSynch				= wait until a scanner synch pulse arrives
%
%	SetButtonReadoutTime(t) 	= blocks individual button readout after a button press for 't' seconds (detection of other buttons is still possible)
%	SetButtonBoxReadoutTime(t)	= blocks the whole button box readout after a button press for 't' seconds (detection of other buttons is also not possible)
%	WaitForButtonPress			= wait until a button is pressed
%
% USAGE
%
% Initialise:
% 	SSO = ScannerSynchClass;
%
% Close:
% 	SSO.delete;
%
% Example for scanner synch pulse:
% 	SSO.SetSynchReadoutTime(0.5);
% 	% SSO.TR = 2; % for emulation
%	while SSO.SynchCount ~= 10 % polls 10 pulses
%   	SSO.WaitForSynch;
%   	fprintf('Pulse %d: %2.3f\n',SSO.SynchCount,SSO.TimeOfLastPulse);
%	end
%
% Example for buttons:
% 	SSO.SetButtonReadoutTime(0.5); % block individual buttons
%	% SSO.SetButtonBoxReadoutTime(0.5); % block the whole buttonbox
%	n = 0;
%	SSO.ResetClock;
%	while n ~= 10 % polls 10 button presses
%   	SSO.WaitForButtonPress;
%    	n = n + 1;
%    	fprintf('Button %d ',SSO.LastButtonPress);
%    	fprintf('pressed: %2.3fs\n',SSO.TimeOfLastButtonPress);
%	end
%_______________________________________________________________________
% Copyright (C) 2015 MRC CBSU Cambridge
%
% Tibor Auer: tibor.auer@mrc-cbu.cam.ac.uk
%_______________________________________________________________________

classdef ScannerSynchClass < handle
    
    
    properties
        TR = 0 % second (timeout for WaitForSynch)
    end
    
    properties (SetAccess = private)
        SynchCount = 0
        LastButtonPress
    end
    
    properties (Access = private)
        
        DAQ
        nChannels
        
        tID % internal timer
        
        Data
        TOA % Time of access 1*n
        ReadoutTime = 0 % sec to store data before refresh 1*n
        TimeoutTime = Inf % Additional method to set a maximum wait time for button press
        BBoxReadout = false
        timeout_timer
        
    end
    
    properties (Dependent)
        IsValid
        
        Buttons
        Synch
        Clock
        
        TimeOfLastPulse
        TimeOfLastButtonPress
    end
    
    methods
        
        %% Contructor and destructor
        function obj = ScannerSynchClass
            fprintf('Initialising Scanner Synch...');
            % Create session
            warning off daq:Session:onDemandOnlyChannelsAdded
            obj.DAQ = daq.createSession('ni');
            % Add channels for scanner pulse
            obj.DAQ.addDigitalChannel('Dev1', 'port0/line0', 'InputOnly');
            % Add channels for button 1-4
            obj.DAQ.addDigitalChannel('Dev1', 'port0/line1', 'InputOnly');
            obj.DAQ.addDigitalChannel('Dev1', 'port0/line2', 'InputOnly');
            obj.DAQ.addDigitalChannel('Dev1', 'port0/line3', 'InputOnly');
            obj.DAQ.addDigitalChannel('Dev1', 'port0/line4', 'InputOnly');
            
            if ~obj.IsValid
                warning('WARNING: Scanner Synch is not open!\n');
            end
            
            obj.nChannels = numel(obj.DAQ.Channels);
            
            obj.Data = zeros(1,obj.nChannels);
            obj.ReadoutTime = obj.ReadoutTime * ones(1,obj.nChannels);
            obj.TimeoutTime = obj.TimeoutTime * ones(1,obj.nChannels);

            obj.ResetClock;
            fprintf('Done\n');
        end
        
        function delete(obj)
            fprintf('Scanner Synch is closing...');
            obj.DAQ.release();
            delete(obj.DAQ);
            warning on daq:Session:onDemandOnlyChannelsAdded
            fprintf('Done\n');
        end
        
        %% Utils
        function val = get.IsValid(obj)
            val = ~isempty(obj.DAQ) && obj.DAQ.isvalid;
        end
        
        function ResetClock(obj)
            obj.tID = tic;
            obj.TOA = zeros(1,obj.nChannels);
        end
        
        function val = get.Clock(obj)
            val = toc(obj.tID);
        end
        
        % Scanner Pulse
        function ResetSynchCount(obj)
            obj.SynchCount = 0;
        end
        
        function SetSynchReadoutTime(obj,t)
            obj.ReadoutTime(1) = t;
        end
        
        function WaitForSynch(obj)
            while ~obj.Synch
            end
            if ~obj.SynchCount
                obj.ResetClock;
            end
            obj.SynchCount = obj.SynchCount + 1;
        end
        
        function val = get.TimeOfLastPulse(obj)
            val = obj.TOA(1);
        end
        
        % Buttons
        function SetButtonReadoutTime(obj,t)
            obj.ReadoutTime(2:end) = t;
            obj.BBoxReadout = false;
        end
        
        function SetButtonBoxReadoutTime(obj,t)
            obj.ReadoutTime(2:end) = t;
            obj.BBoxReadout = true;
        end
        
        function SetButtonBoxTimeoutTime(obj,t)
            obj.TimeoutTime(2:end) = t;
            obj.timeout_timer = tic;
        end
        
        function WaitForButtonPress(obj,ind)
            while ~obj.Buttons || (nargin == 2 && ~any(obj.LastButtonPress == ind))
            end
            clear timeout_timer;
        end
        
        function val = get.TimeOfLastButtonPress(obj)
            val = max(obj.TOA(2:end));
        end
        
        %% Low level access
        function Refresh(obj)
            % get data
            data = inputSingleScan(obj.DAQ); data(1:end) = ~data(1:end); % 2-5: buttons 1-4 inverted
            t = toc(obj.tID);
            
            % scanner synch pulse emulation
            data(1) = data(1) || (obj.TR && (~obj.SynchCount || (t-obj.TOA(1) >= obj.TR)));
            
            if obj.BBoxReadout, obj.TOA(2:end) = max(obj.TOA(2:end)); end
            ind = obj.ReadoutTime < (t-obj.TOA);
            obj.Data(ind) = data(ind);
            obj.TOA(logical(obj.Data)) = t;
        end
        function val = get.Synch(obj)
            val = 0;
            obj.Refresh;
            if obj.Data(1)
                obj.Data(1) = 0;
                val = 1;
            end
        end
        function val = get.Buttons(obj)
            val = 0;
            obj.Refresh;
            if any(obj.Data(2:end))
                obj.LastButtonPress = find(obj.Data(2:end));
                val = 1;
                obj.Data(1:end) = 0;
            elseif ~isempty('obj.timeout_timer')
                timenow = toc(obj.timeout_timer);
                if timenow >= obj.TimeoutTime(2)
                    val = 1;
                    obj.LastButtonPress = NaN;
                    obj.TimeoutTime(2:end) = Inf;
                    obj.Data(1:end) = 0;
                end
            end
            
        end
        
    end
    
end