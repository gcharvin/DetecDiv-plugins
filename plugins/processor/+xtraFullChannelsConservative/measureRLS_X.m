function measureRLS_X(obj,param,varargin)



  classif= param.classifierName ;
  classifstrid=classif.strid;

obj.results.RLS.(['from_' classifstrid])=RLS(obj,classifstrid,param); %struct() use to keep measureRLS2 code

%=========================================RLS============================================
function [rls,rlsResults]=RLS(roi,classifstrid,param)
        
        classes=roi.results.(classifstrid).classes;
        id=roi.results.(classifstrid).id; % results for classification
        proba=roi.results.(classifstrid).prob;
        
        divTimes=computeDivtime(id,proba,classes,param);
        
        rlsResults.divDuration=divTimes.duration;
        rlsResults.frameBirth=divTimes.frameBirth;
        rlsResults.frameEnd=divTimes.frameEnd;
        rlsResults.endType=divTimes.endType;
        rlsResults.framediv=divTimes.framediv;
        rlsResults.sep=[];
        rlsResults.name=roi.id;
%         rlsResults.roiid=i;
        rlsResults.ndiv=divTimes.ndiv;
        if numel(divTimes.framediv)>0
            rlsResults.totaltime=[divTimes.framediv(1)-divTimes.frameBirth, cumsum(divTimes.duration)+divTimes.framediv(1)-divTimes.frameBirth];
        else
            rlsResults.totaltime=0;
        end
        rlsResults.rules=[];
        rlsResults.groundtruth=0;
        rlsResults.divSignal=[];
        
%         divSignal=computeSignalDiv(roi,rlsResults);
%         rlsResults.divSignal=divSignal;
  
        rlsResults.bounds=param.Frames;      
        %sep
        rlsResults.sep=findSync(rlsResults);
        rls=rlsResults;

%% =========================================DIVTIMES=================================================
function [divTimes]=computeDivtime(id,proba,classes,param)
% if numel(param.Frames)==2
%     id=id(param.Frames(1):param.Frames(2));
% end
divTimes=[];

% first identify frame corresponding to death or clog and birth (non
% empty cavity)
        deathid=findclassid(classes,'dead');
        clogid=findclassid(classes,'clog');
        lbid=findclassid(classes,'large');
        smid=findclassid(classes,'small');
        unbuddedid=findclassid(classes,'unbud');
        emptyid=findclassid(classes,'empty');
        
        %% post process
        % if (proba~=-1) & (param.postProcessing==1)
        %     probaPP=proba;
        %     probaPP(smid,:)=medfilt1(probaPP(smid,:),4);
        %     probaPP(lbid,:)=medfilt1(probaPP(lbid,:),4);
        % 
        %     [~,idPP]=max(probaPP,[],1);
        %     id=idPP;
        % end

        
       if (proba~=-1) & (param.postProcessing==1) %%substituted to replace the medfilt1 function which requires the Signal Processing tool, that misteriously disappeared one day; have no idea whether it is a good replacement
            probaPP=proba;

            for kkkk = 3:(numel(probaPP(smid,:))-2)
            probaPP(smid,kkkk)=median(probaPP(smid,kkkk-2:kkkk+2));
            end
            for kkkkk = 3:(numel(probaPP(lbid,:))-2)
            probaPP(lbid,kkkkk)=median(probaPP(lbid,kkkkk-2:kkkkk+2));
            end
            [~,idPP]=max(probaPP,[],1);
            id=idPP;
        end


        %%
        
        %===1// find BIRTH===
        
        firstunb=find(id==unbuddedid,1,'first');
        firstsm=find(id==smid,1,'first');
        firstlg=find(id==lbid,1,'first');

        frameBirth=min([firstunb,firstsm,firstlg]);
        if isempty(frameBirth)
         frameBirth=NaN;
        end
        
        %===2// Identify potential END===
        %==find potential first EMPTY frame, after birth
        frameFirstEmptiedAfterBirth=NaN;
        bwEmpty=(id==emptyid);
        bwEmptyLabeled=bwlabel(bwEmpty);
        for k=1:max(bwEmptyLabeled)
            bwEmpty=(bwEmptyLabeled==k);
            if sum(bwEmpty)> 2 && find(bwEmpty,1,'first')>frameBirth
                frameFirstEmptiedAfterBirth=find(bwEmpty,1,'first');
                break
            end
        end
        
        %==post-process empty : if empty very early: check the next rls
        if frameFirstEmptiedAfterBirth<param.EmptyThresholdNext%frameFirstEmptiedAfterBirth>param.EmptyThresholdDiscard
            frameAfterFirstEmpty=find(bwEmpty,1,'last');
            %search from after the first empty islet (after first birth)
            %until the end
            firstunb=frameAfterFirstEmpty -1 +find(id(frameAfterFirstEmpty:end)==unbuddedid,1,'first');
            firstsm=frameAfterFirstEmpty -1 +find(id(frameAfterFirstEmpty:end)==smid,1,'first');
            firstlg=frameAfterFirstEmpty -1 +find(id(frameAfterFirstEmpty:end)==lbid,1,'first');
            if numel(firstunb)==0 %isempty
                firstunb=NaN;
            end
            if numel(firstsm)==0
                firstsm=NaN;
            end
            if numel(firstlg)==0
                firstlg=NaN;
            end
            frameBirth=min([firstunb,firstsm,firstlg]);
            frameFirstEmptiedAfterBirth=NaN;
            bwEmpty=(id((frameAfterFirstEmpty+1):end)==emptyid);
            bwEmptyLabeled=bwlabel(bwEmpty);
            for k=1:max(bwEmptyLabeled)
                bwEmpty=(bwEmptyLabeled==k);
                if sum(bwEmpty)> 2 && find(bwEmpty,1,'first')>frameBirth
                    frameFirstEmptiedAfterBirth=find(bwEmpty,1,'first');
                    break
                end
            end
        end
        %
        

        
        %==find DEATH (need param.DeathThreshold frames to be validated)======
        frameDeath=NaN;
        if ~isnan(frameBirth)
            idpostBirth=id;
            idpostBirth(1:frameBirth)=0;%only consider death if cell is born (to ignore death if first images of roi is death=
            bwDeath=(idpostBirth==deathid);
            bwDeath(1:frameBirth)=0; %useless?
            bwDeathLabeled=bwlabel(bwDeath);
            for k=1:max(bwDeathLabeled)
                bwDeath=(bwDeathLabeled==k);
                if sum(bwDeath)>= param.DeathThreshold || find(bwDeath,1,'last')==numel(id) || (id(find(bwDeath,1,'last')+1)==emptyid)% if ... or if the last frame is "dead",  or if dead is followed by empty (dead cells often squeeze through the trap), then consider as death
                    frameDeath=find(bwDeath,1,'first');
                    break
                end
            end
        end
        %
        
        
        %==find potential first CLOG==============
        frameClog=NaN;
        if ~isnan(frameBirth)
            idpostBirth=id;
            idpostBirth(1:frameBirth)=0;%only consider clog if cell is born (to ignore clog if first images of roi is clog=
            bwClog=(idpostBirth==clogid);
            bwClog(1:frameBirth)=0; %useless?
            bwClogLabeled=bwlabel(bwClog);
            for k=1:max(bwClogLabeled)
                bwClog=(bwClogLabeled==k);
                if sum(bwClog)>= param.ClogThreshold
                    frameClog=find(bwClog,1,'first');
                    break
                end
            end
        end
        %         if ~isnan(frameBirth)
        %             frameClog=find((idpostBirth==clogid),1,'first');
        %         end
        %
        
        
        %==find potential division arrest==========
        frameArrest=NaN;
        for arrestid=[unbuddedid,smid,lbid]
            bwArrest=(id==arrestid);
            bwArrestLabel=bwlabel(bwArrest);
            for k=1:max(bwArrestLabel)
                bwArrest=(bwArrestLabel==k);
                if sum(bwArrest)> param.ArrestThreshold
                    if ~isnan(frameArrest)
                        frameArrest=min(frameArrest,(find(bwArrest,1,'first')+ param.ArrestThreshold));
                    else
                        frameArrest=find(bwArrest,1,'first')+ param.ArrestThreshold;
                    end
                    break
                end
            end
        end
        %
        
        %===3/ find END===
        if isnan(frameBirth) %if timeseries has never seen unb, small or large
            frameEnd=NaN;
            endType='NeverBorn';
        else
            frameEnd=min([frameClog, frameDeath, frameFirstEmptiedAfterBirth, frameArrest]);
            if isnan(frameEnd) % cell is not dead or clogged or empty, TO DO: SEPARATE BETWEEN DEATH AND CENSOR
                frameEnd=numel(id);
                %machin.censor=1;
            end
            endTypeid=find([frameClog, frameDeath, frameFirstEmptiedAfterBirth, frameArrest, numel(id)]==frameEnd,1,'last');
            endTypeList={'Clog', 'Death', 'Emptied', 'Arrest', 'stillAlive'};
            endType=endTypeList{endTypeid};
        end
        %
        
     
        %=====Div counting=====
        %
        %
        divFrames=[];
        startAfterBudEmergence=0;
        if ~isnan(frameBirth)
            %===divided before start of timelapse==?
            if id(frameBirth)==smid || id(frameBirth)==lbid
                startAfterBudEmergence=1;
            end
            
            %==detect bud emergence==
            for j=frameBirth:frameEnd-1
                 if (id(j)==lbid && id(j+1)==smid) || (id(j)==unbuddedid  && id(j+1)==smid) % bud has emerged %original line
%               if (id(j)==lbid && id(j+1)==smid) || (id(j)==unbuddedid  &&  id(j+1)==smid && (id(j-1)==lbid || id(j-1)==emptyid)) %think about it
                    divFrames=[divFrames j+1];
                end
            end
        end
        %
        if numel(divFrames)==0
            divFrames=NaN;
        end
        divTimes.frameBirth=frameBirth;
        divTimes.frameEnd=frameEnd;
        divTimes.endType=endType;
        divTimes.framediv=divFrames;
        divTimes.duration=diff(divFrames); % division times !
        divTimes.ndiv=sum(~isnan([divTimes.framediv]));
        %if timelapse started while the cell is small or large
        if startAfterBudEmergence==1
            divTimes.ndiv=divTimes.ndiv+1;
        end



%%
%=============================================SEP==========================================
function [syncPoint]=findSync(rls)
align=1; %1: SEP, 2: death
syncType={'birthSynced', 'SEPSynced','deathSynced'};
threshStart=1;
numrls=numel(rls);

divDur=rls.divDuration;
if numel(divDur)>1
  [syncPoint,~]=xtraFullChannelsConservative.findSEP(divDur,1); %find SEP using classical xhi² fit based on div frequency
else syncPoint=NaN;
end


function clid=findclassid(classes,str)
clid=[];
for ck=1:numel(classes)
    if strcmp(classes{ck},str)
        clid=ck;
        break;
    end
end
