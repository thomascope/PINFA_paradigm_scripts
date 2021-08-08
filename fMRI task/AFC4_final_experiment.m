
% A 7T experiment looking at MVPA of word triples in a paradigm where
% expectations and sensory detail are parametrically varied while clarity
% ratings are requested from the participant. Designed to use sparse
% imaging.
% Changelog since first pilot:
% Now allocates exactly 3 TRs for response trial.
% Trialtype recording fixed
% Vocoder channels now 4 and 16
%
% NBNBNBNBNB: TO USE IN A REAL SCANNER CHANGE ScannerSynchClass line:
% data = inputSingleScan(obj.DAQ); data(1:end) = ~data(1:end); % 2-5: buttons 1-4 inverted
% to
% data = inputSingleScan(obj.DAQ); data(2:end) = ~data(2:end); % 2-5: buttons 1-4 inverted

%% Setup experimental parameters
global Subj_num hand
if isempty(Subj_num) ~= 1 && isempty(hand) ~= 1
    useprev = input('Would you like to use previous input options? Please enter y or n: ','s');
    while strcmp(useprev,'y') == 0 && strcmp(useprev,'n') == 0
        useprev = input('Please enter y or n only: ','s');
    end
    if strcmp(useprev,'n')==1
        clear all
        global Subj_num hand
    end
end
if isempty(Subj_num) == 1 || isempty(hand) == 1
    Subj_num = input('Enter listener initials: \n\n ','s');
    hand = input('Enter 1 for response box, or 2 for keyboard with simulated scanner pulses: \n\n ');
end

run_number = input('Please enter the run number: \n\n ');

AFCs = input('How many alternatives would you like for the forced choice? Only 2 and 4 implemented at present: \n\n ');

%Screen('Preference', 'SkipSyncTests', 1) %FOR PILOTING ONLY
Screen('Preference', 'SkipSyncTests', 0)
clear SSO

TR = 2.5; %Approximate scanner TR
TA = 1.5; %Approximate scanner TA
% default_sound_delay = 1.05; %Delay between written and spoken words
default_sound_delay = 0.7; %Delay between written and spoken words
default_response_delay = 1.05; %Delay between spoken word and response cue
default_sound_time = 0.2; %Intended delay between offset of scanner noise and onset of sound to account for masking
num_dummies = 3;
numsecstowaitforresponse = 6.0; % Add approx 2.75s to this for a response trial length (using TR=2.5, TA=1.5)
%numsecstowaitforresponse = 0; %For debug
Numrepsperblock = 2; %Number of stimulus sets per block
Numblocks = 1; %Not yet implemented - re-run the script and change run number to run next block

c = clock;
todays_date = sprintf('%04.0f%02.0f%02.0f',c(1),c(2),c(3));
Expt = mfilename('fullpath'); %for your information

DIRS = pwd;
sdir = [DIRS '/Filtered_RMS_Vocoded_Stimuli/']; %NB: NEED TO CHANGE THIS TO FILTERED STIMULI AFTER FILE AVAILABLE
ddir = [DIRS '/data/'];
if ~exist(sdir,'dir')
    error('Stimulus directory not found, are you in the correct folder?')
end
if ~exist(ddir,'dir')
    mkdir(ddir)
end

if exist([ddir 'AFC_7T_' Subj_num '_Run_' num2str(run_number) '_' todays_date '.mat'],'file')
    suretogo = input('A data file from today with this subject and run number already exists, are you sure you want to continue - data will be overwritten? y or n: \n\n','s');
    if suretogo ~= 'y'
        error('Try again please :)')
    end
end

save([ddir 'AFC_7T_' Subj_num '_Run_'  num2str(run_number) '_' todays_date '.mat'],'Subj_num','todays_date','TR','TA','Expt','Numrepsperblock','Numblocks','run_number','hand','AFCs');
%% Setup scanner sync

try
    spm_rmpath %SPM Conflicts with NIDAQ
    fprintf('Please note: I have removed SPM from your path for this session as it conflicts with NIDAQ \n')
catch
end
SSO = ScannerSynchClass;

SSO.SetSynchReadoutTime(0.1); %Set a minimum value here to prevent accidental double readout, but affects the amount of time after a response before pulses can be detected
%SSO.TR = TR;  % For emulation mode
if hand == 2
    SSO.TR = TR;  % For emulation mode
end

%% Setup stimuli and load into memory

wordlist = {'bard','barge','lard','large','pit','pick','kit','kick','debt','deck','net','neck','robe','road','lobe','load'};
% vocoder_channels = {'3','16'};
vocoder_channels = {'3','15'};
%vocoder_channels = {'4','16'};
%vocoder_channels = {'6','16'};
neutral_stim = {'XXXX'};
%cue_types = {'Match','MisMatch','Neutral'};
cue_types = {'Match','MisMatch'};

save([ddir 'AFC_7T_' Subj_num '_Run_' num2str(run_number) '_' todays_date '.mat'],'wordlist','vocoder_channels','neutral_stim','cue_types','-append');

disp('Loading sounds');
fs = 44100;
sig = [];
%Create a cell array arranged first by word then by sensory detail
for i = 1:length(wordlist)
    for j = 1:length(vocoder_channels)
        file = [sdir wordlist{i} '_noise_n_greenwood_half_30_' vocoder_channels{j} '.wav'];
        [sig{i}{j}.y,fs_check] = audioread(file); %Prepare sound in memory
        
        if size(sig{i}{j}.y,2) == 1
            error('The sound is mono, when it should be stereo. The most likely reason for this is that you have forgotten to do EQ filtering')
        %sig{i}{j}.y(:,2) = sig{i}{j}.y;
        end
        sig{i}{j}.y = sig{i}{j}.y';
        if fs ~= fs_check,
            error('Sampling rate not as expected');
        end
    end
end



%% Setup response mapping

if (hand==1); % use hand to determine response mapping
    %This is button box condition
elseif (hand ==2);
    resp1=KbName('1!');
    resp2=KbName('2@');
    resp3=KbName('3#');
    resp4=KbName('4$');
end


%% Start experiment
pulse_times = [];
sound_start_times = [];
sound_start_pulses = [];
SSO.ResetSynchCount
SSO.ResetClock

fprintf('Now listening for scanner pulses. You should get feedback in the command window from the second pulse \n\n\n');

AssertOpenGL;

% get screen
screens = Screen('Screens');
screenNumber = max(screens); %For secondary display
%screenNumber = 1; %For primary display
%HideCursor;

% set window
pixdepth = 32;
buffermode = 2; % double buffer
[w, wRect]=Screen('OpenWindow', screenNumber, 0, [], pixdepth, buffermode);
[width, height] = Screen('WindowSize', w);
Screen(w,'BlendFunction',GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

% set colours
gray = GrayIndex(screenNumber);
gray = gray/4; %account for very bright projector!
%white = WhiteIndex(screenNumber);
white = GrayIndex(screenNumber); %To avoid afterimages
black = BlackIndex(screenNumber);

% set priority
priorityLevel = MaxPriority(w);
Priority(priorityLevel);

% clear screen
Screen('FillRect',w, gray);
Screen('Flip', w);

% set text parameters
yoffset = 0;
textsize = 32;

drawText('The experiment will start soon', w, yoffset, white, textsize);
Screen('Flip',w);

%InitializePsychSound %Can't get psychtoolbox to work with USB sound card
%at the minute

while SSO.SynchCount < num_dummies % Waits N pulses before starting experiment
    SSO.WaitForSynch;
    if SSO.SynchCount >=2
        fprintf('Pulse %d: Measured TR = %2.3fs\n\n\n',...
            SSO.SynchCount,...
            [SSO.TimeOfLastPulse-pulse_times(end)]);
    end
    pulse_times(end+1) = SSO.TimeOfLastPulse;
    save([ddir 'AFC_7T_' Subj_num '_Run_' num2str(run_number) '_' todays_date '.mat'],'pulse_times','-append');
end

Screen('Flip',w);

%% Now loop through trials

pulse_numbers_at_normal_trialstart = [];
pulse_numbers_at_response_trialstart = [];
pulse_numbers_at_writtenonly_trialstart = [];
imputed_pulse_numbers_at_normal_trialstart = [];
imputed_pulse_numbers_at_response_trialstart = [];
imputed_pulse_numbers_at_writtenonly_trialstart = [];
cue_onset_response = [];
cue_offset_response = [];
cue_onset_written = [];
cue_offset_written = [];
this_cue_delay_written= [];
this_cue_delay_response= [];
averaged_measured_TR = mean(diff(pulse_times(1:end)));
sound_start_pulses = [SSO.SynchCount+1];
i = 1;

if hand == 2
    ListenChar(1);
    [KeyIsDown, endrt, KeyCode] = KbCheck;
end

%XXX Need to define a trial_order.mat with order of cues and presented words,
%with stimulus types
load(['fourth_AFC_run_order_' num2str(run_number) '.mat']);
response_order = load(['fourth_AFC_run_order_response.mat']);
% %This is now dealt with in the trial creation script
% this_mismatch_cue = zeros(1,length(this_word));
% for i = 1:length(this_word) %Alternate between mismatch triplets
%     if mod(i,2)==0
%         this_mismatch_cue(i) = mod(this_word(i) + 8,length(wordlist));
%         response_order.this_mismatch_cue(i) = mod(response_order.this_word(i) + 8,length(wordlist));
%     else
%         this_mismatch_cue(i) = mod(this_word(i) + 4,length(wordlist));
%         response_order.this_mismatch_cue(i) = mod(response_order.this_word(i) + 4,length(wordlist));
%     end
%     if this_mismatch_cue(i) == 0
%         this_mismatch_cue(i) = 16;
%     end
%     if response_order.this_mismatch_cue(i) == 0
%         response_order.this_mismatch_cue(i) = 16;
%     end
% end
save([ddir 'AFC_7T_' Subj_num '_Run_' num2str(run_number) '_' todays_date '.mat'],'this_cue_types','this_vocoder_channels','this_word','this_mismatch_cue','response_order','written_trial_word','-append');
%these_response_combinations = shuffle(all_response_combinations_sorted(:,runnum:7:end));
resp = [];
all_rts = [];
all_mixes = [];
all_trial_targets = [];
all_options = [];

this_response_delay = [];
trialtype = cell(0);
for i = 1:(length(wordlist)*length(vocoder_channels)*length(cue_types)*Numrepsperblock);
    
    if strcmp('Match',cue_types{this_cue_types(i)})
        trialtype{end+1} = ['Normal Trial: ' cue_types{this_cue_types(i)} '_' vocoder_channels{this_vocoder_channels(i)} '_channels_written_' wordlist{this_word(i)} '_spoken_'  wordlist{this_word(i)}];
        disp(trialtype{end})
        drawText(upper(wordlist{this_word(i)}), w, yoffset, white, textsize);
    elseif strcmp('MisMatch',cue_types{this_cue_types(i)})
        trialtype{end+1} = ['Normal Trial: ' cue_types{this_cue_types(i)} '_' vocoder_channels{this_vocoder_channels(i)} '_channels_written_' wordlist{this_mismatch_cue(i)} '_spoken_'  wordlist{this_word(i)}];
        disp(trialtype{end})
        drawText(upper(wordlist{this_mismatch_cue(i)}), w, yoffset, white, textsize);
    elseif strcmp('Neutral',cue_types{this_cue_types(i)})
        trialtype{end+1} = ['Normal Trial: ' cue_types{this_cue_types(i)} '_' vocoder_channels{this_vocoder_channels(i)} '_channels_written_' neutral_stim{1} '_spoken_'  wordlist{this_word(i)}];
        disp(trialtype{end})
        drawText(neutral_stim{1}, w, yoffset, white, textsize);
    end
    
    SSO.WaitForSynch;
    fprintf('Trial %d: Measured Delay Since Last Trial = %2.3fs\n\n\n',...
        SSO.SynchCount-num_dummies,...
        [SSO.TimeOfLastPulse-pulse_times(end)]);
    
    start_time = GetSecs;
    pulse_times(end+1) = SSO.TimeOfLastPulse;
    pulse_numbers_at_normal_trialstart(end+1) = SSO.SynchCount;
    
    imputed_pulse_numbers_at_normal_trialstart(end+1) = 1+round((pulse_times(end)-pulse_times(1))/averaged_measured_TR); %First pulse_time recorded at second scanner pulse
    fprintf('I impute that pulse number %d just occurred; please check this with scanner console \n\n', imputed_pulse_numbers_at_normal_trialstart(end))
    
    %this_cue_delay(i) = 1.2 + 0.1*rand;
    this_cue_delay(i) = TR-default_sound_delay-(TR-TA-default_sound_time);
    WaitSecs('UntilTime',start_time+this_cue_delay(i));
    
    Screen('Flip',w);
    cue_onset(i) = SSO.Clock;
    WaitSecs(0.5);
    Screen('Flip',w);
    cue_offset(i) = SSO.Clock;
    
    %this_sound_delay(i) = 1 + 0.1*rand;
    this_sound_delay(i) = default_sound_delay;
    WaitSecs('UntilTime',start_time+this_cue_delay(i)+this_sound_delay(i));
    sound_start_times(end+1) = SSO.Clock;
    %Snd('Play',  sig{this_word(i)}{this_vocoder_channels(i)}.y, fs);
    sound(sig{this_word(i)}{this_vocoder_channels(i)}.y, fs);
    
    save([ddir 'AFC_7T_' Subj_num '_Run_' num2str(run_number) '_' todays_date '.mat'],'resp','all_rts','this_cue_delay','this_sound_delay','this_response_delay','trialtype','sound_start_times','pulse_times','pulse_numbers_at_normal_trialstart','imputed_pulse_numbers_at_normal_trialstart','pulse_numbers_at_response_trialstart','pulse_numbers_at_writtenonly_trialstart','imputed_pulse_numbers_at_response_trialstart','imputed_pulse_numbers_at_writtenonly_trialstart','start_time','cue_onset','cue_offset','-append');
    
    if ismember(i,response_trial_here)
        [~,locB] = ismember(i,response_trial_here);
        j = locB+(length(response_trial_here)*(run_number-1));
        if strcmp('Match',cue_types{response_order.this_cue_types(j)})
            trialtype{end+1} = ['Response Trial: ' cue_types{response_order.this_cue_types(j)} '_' vocoder_channels{response_order.this_vocoder_channels(j)} '_channels_written_' wordlist{response_order.this_word(j)} '_spoken_'  wordlist{response_order.this_word(j)}];
            disp(trialtype{end})
            drawText(upper(wordlist{response_order.this_word(j)}), w, yoffset, white, textsize);
        elseif strcmp('MisMatch',cue_types{response_order.this_cue_types(j)})
            trialtype{end+1} = ['Response Trial: ' cue_types{response_order.this_cue_types(j)} '_' vocoder_channels{response_order.this_vocoder_channels(j)} '_channels_written_' wordlist{response_order.this_mismatch_cue(j)} '_spoken_'  wordlist{response_order.this_word(j)}];
            disp(trialtype{end})
            drawText(upper(wordlist{response_order.this_mismatch_cue(j)}), w, yoffset, white, textsize);
        elseif strcmp('Neutral',cue_types{response_order.this_cue_types(j)})
            trialtype{end+1} = ['Response Trial: ' cue_types{response_order.this_cue_types(j)} '_' vocoder_channels{response_order.this_vocoder_channels(j)} '_channels_written_' neutral_stim{1} '_spoken_'  wordlist{response_order.this_word(j)}];
            disp(trialtype{end})
            drawText(neutral_stim{1}, w, yoffset, white, textsize);
        end
        
        SSO.WaitForSynch;
        fprintf('Trial %d: Measured Delay Since Last Trial = %2.3fs\n\n\n',...
            SSO.SynchCount-num_dummies,...
            [SSO.TimeOfLastPulse-pulse_times(end)]);
        
        start_time = GetSecs;
        pulse_times(end+1) = SSO.TimeOfLastPulse;
        pulse_numbers_at_response_trialstart(end+1) = SSO.SynchCount;
        
        imputed_pulse_numbers_at_response_trialstart(end+1) = 1+round((pulse_times(end)-pulse_times(1))/averaged_measured_TR); %First pulse_time recorded at second scanner pulse
        fprintf('I impute that pulse number %d just occurred; please check this with scanner console \n\n', imputed_pulse_numbers_at_response_trialstart(end))
        
        %this_cue_delay_response(j) = 1.2 + 0.1*rand;
        this_cue_delay_response(j) = TR-default_sound_delay-(TR-TA-default_sound_time);
        WaitSecs('UntilTime',start_time+this_cue_delay_response(j));
        
        Screen('Flip',w);
        cue_onset_response(j) = SSO.Clock;
        WaitSecs(0.5);
        Screen('Flip',w);
        cue_offset_response(j) = SSO.Clock;
        
        %this_sound_delay_response(j) = 1 + 0.1*rand;
        this_sound_delay_response(j) = default_sound_delay;
        WaitSecs('UntilTime',start_time+this_cue_delay_response(j)+this_sound_delay_response(j));
        sound_start_times(end+1) = SSO.Clock;
        %Snd('Play',  sig{response_order.this_word(j)}{response_order.this_vocoder_channels(j)}.y, fs);
        sound(sig{response_order.this_word(j)}{response_order.this_vocoder_channels(j)}.y, fs);
        
        
        if AFCs == 4  %Use other exemplars with the same vowel
            correct_answer = mod(response_order.this_word(j),4);
            if correct_answer == 0;
                correct_answer = 4;
            end
            options_set = ceil(response_order.this_word(j)/4);
            options = wordlist(4*(options_set-1)+1:4*(options_set-1)+4);
            mixitup = randperm(4);
            options = options(mixitup);
            trial_target = find(mixitup==correct_answer);
            all_mixes = [all_mixes; mixitup];
            all_trial_targets = [all_trial_targets; trial_target];
            all_options = [all_options; options];
            
            %this_response_delay(j) = 1 + 0.1*rand;
            this_response_delay(j) = default_response_delay;
            
            listoptions=['1: ', upper(options{1}),'   2: ', upper(options{2}),'   3: ', upper(options{3}),'   4: ', upper(options{4})];
            
        elseif AFCs == 2 %Use the next vowel along
            correct_answer = 1;
            distractor = mod(response_order.this_word(j)+4,16);
            distractor(distractor==0) = 16;
            options = wordlist([response_order.this_word(j), distractor]);
            mixitup = randperm(2);
            options = options(mixitup);
            trial_target = find(mixitup==correct_answer);
            all_mixes = [all_mixes; mixitup];
            all_trial_targets = [all_trial_targets; trial_target];
            all_options = [all_options; options];
            
            %this_response_delay(j) = 1 + 0.1*rand;
            this_response_delay(j) = default_response_delay;
            
            listoptions=['1: ', upper(options{1}),'          2: ', upper(options{2})];


            
        end
        
        
        drawText(['What did you hear?'], w, yoffset-150, white, round(textsize*2/3)); % XXX MAKE THIS RESPONSE CUE BETTER
        drawText(listoptions, w, yoffset, white, textsize);
        
        WaitSecs('UntilTime',start_time+this_cue_delay_response(j)+this_sound_delay_response(j)+this_response_delay(j));
        Screen('Flip',w);
        
        %%% RESPONSE COLLECTION SECTION
        
        startrt = GetSecs;
        if hand == 1
            SSO.SetButtonBoxTimeoutTime(numsecstowaitforresponse) % New addition to Scannersyncclassthat should mean we don't wait longer than the specified max time
            
            SSO.WaitForButtonPress;
            
            endrt = GetSecs;
            rt = round(1000*(endrt-startrt));   % get rt
            
            resp(j) = SSO.LastButtonPress;
            if ~isnan(resp(j))
                fprintf('Button %d ',resp(j));
                fprintf('pressed RT: %d\n',rt);
            else
                fprintf('No button pressed after %d milliseconds, moving on\n',rt);
            end
            
            
        elseif hand == 2
            [KeyIsDown, endrt, KeyCode] = KbCheck;
            while (1),
                % quit experiment, if desired
                if ( KeyIsDown==1 & KeyCode(27)==1 ) %was "esc" pressed?
                    Screen('FillRect', w, gray);
                    Screen('Flip', w);
                    WaitSecs(0.500);
                    Screen('CloseAll');
                    ShowCursor;
                    ListenChar;
                    Priority(0);
                    %Snd('Quiet');
                    disp('Experimenter exit ...');
                    error('exit');
                end
                if KeyCode(resp1)==1
                    resp(j) = 1;
                    break;
                elseif KeyCode(resp2)==1
                    resp(j) = 2;
                    break;
                elseif KeyCode(resp3)==1
                    resp(j) = 3;
                    break;
                elseif KeyCode(resp4)==1
                    resp(j) = 4;
                    break;
                end
                [KeyIsDown, endrt, KeyCode] = KbCheck;
                endrt = GetSecs;
                rt = round(1000*(endrt-startrt));   % get rt
            end
        end
        Screen('Flip',w);
        all_rts(j) = rt;
        save([ddir 'AFC_7T_' Subj_num '_Run_' num2str(run_number) '_' todays_date '.mat'],'resp','all_rts','this_cue_delay_response','this_sound_delay','this_response_delay','trialtype','sound_start_times','pulse_times','pulse_numbers_at_normal_trialstart','imputed_pulse_numbers_at_normal_trialstart','pulse_numbers_at_response_trialstart','pulse_numbers_at_writtenonly_trialstart','imputed_pulse_numbers_at_response_trialstart','imputed_pulse_numbers_at_writtenonly_trialstart','start_time','cue_onset','cue_offset','all_mixes','all_trial_targets','all_options','-append');
        WaitSecs('UntilTime',start_time+this_cue_delay_response(j)+this_sound_delay_response(j)+this_response_delay(j)+numsecstowaitforresponse);
    end
    
    if ismember(i,written_only_trial_here) % Written only trial
        [~,locB] = ismember(i,written_only_trial_here);
        j = locB+(length(written_only_trial_here)*(run_number-1));
        
        trialtype{end+1} = ['Written Only: written_' wordlist{written_trial_word(locB)} '_spoken_none'];
        disp(trialtype{end})
        drawText(upper(wordlist{written_trial_word(locB)}), w, yoffset, white, textsize);
                
        SSO.WaitForSynch;
        fprintf('Trial %d: Measured Delay Since Last Trial = %2.3fs\n\n\n',...
            SSO.SynchCount-num_dummies,...
            [SSO.TimeOfLastPulse-pulse_times(end)]);
        
        pulse_times(end+1) = SSO.TimeOfLastPulse;
        pulse_numbers_at_writtenonly_trialstart(end+1) = SSO.SynchCount;
        imputed_pulse_numbers_at_writtenonly_trialstart(end+1) = 1+round((pulse_times(end)-pulse_times(1))/averaged_measured_TR); %First pulse_time recorded at second scanner pulse
        fprintf('I impute that pulse number %d just occurred; please check this with scanner console \n\n', imputed_pulse_numbers_at_writtenonly_trialstart(end))
        start_time = GetSecs;
        
        %this_cue_delay_written(i) = 1.2 + 0.1*rand;
        this_cue_delay_written(end+1) = TR-default_sound_delay-(TR-TA-default_sound_time);
        WaitSecs('UntilTime',start_time+this_cue_delay_written(end));
        
        Screen('Flip',w);
        cue_onset_written(end+1) = SSO.Clock;
        WaitSecs(0.5);
        Screen('Flip',w);
        cue_offset_written(end+1) = SSO.Clock;
        
        save([ddir 'AFC_7T_' Subj_num '_Run_' num2str(run_number) '_' todays_date '.mat'],'resp','all_rts','this_cue_delay_written','this_sound_delay','this_response_delay','trialtype','sound_start_times','pulse_times','pulse_numbers_at_normal_trialstart','imputed_pulse_numbers_at_normal_trialstart','pulse_numbers_at_response_trialstart','pulse_numbers_at_writtenonly_trialstart','imputed_pulse_numbers_at_response_trialstart','imputed_pulse_numbers_at_writtenonly_trialstart','start_time','cue_onset','cue_offset','cue_onset_response','cue_offset_response','cue_onset_written','cue_offset_written','-append');
    end
end

%% XXX THINGS TO FIX:
%
%
% Previous things to fix now fixed:
% COUNT SCANNER PULSES - PROBABLY BEST TO DIVIDE THE PULSE TIME BY THE AVERAGE TR MEASURED FROM FIRST 12 PULSES - DONE
% FIX TRIALTYPE RECORDING - DONE - now adds to end+1
% ADD IN ENCODING OF ALL TRIAL TYPES AS IT GOES ALONG
% FIGURE OUT WHY MEASURED DELAY IS INCORRECT - DONE SSO.WAITFORBUTTONPRESS
% WAS ACCIDENTALLY PICKING UP SCANNER PULSES. I HAVE CORRECTED SCANNERSYNCHCLASS.
% CREATE UNIFORM LENGTH RESPONSE TRIALS - DONE SSO.SetButtonBoxTimeoutTime METHOD ADDED
% I HAVE MADE IT SO THAT CHANGING THE TR AUTOMATICALLY CHANGES THE STIMULUS PRESENTATION TIMES APPROPRIATELY


SSO.delete









