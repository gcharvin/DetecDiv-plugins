function combine_plus_classi_Xtra_full_channels_7(obj,classif,classifier,classif2,net,varargin)

    obj.load;

%% PreProcessROI
    obj.computeStretchlim;
    tmp = obj.image(:,:,1:3,:);
    strchlm=obj.display.stretchlim;

    for ch = 1:3
    tmpn(:,:,ch,:)=double(imadjustn(tmp(:,:,ch,:),strchlm(:,ch)))/65535;
    end
%% LSTM classification
    vid(:,:,:,:)=uint8(256*tmpn);
    video = centerCrop(vid);

            function videoResized = centerCrop(video)

                sz = size(video);

                if sz(1) < sz(2)
                    % Video is landscape
                    vidx = floor((sz(2) - sz(1))/2);
                    video(:,1:(vidx-1),:,:) = [];
                    video(:,(sz(1)+1):end,:,:) = [];

                elseif sz(2) < sz(1)
                    % Video is portrait
                    vidx = floor((sz(1) - sz(2))/2);
                    video(1:(vidx-1),:,:,:) = [];
                    video((sz(2)+1):end,:,:,:) = [];
                end

                videoResized = imresize(video,[224 224]);
            end
video = gpuArray(video);
[x, prob]=classify(classifier,video,'ExecutionEnvironment',"gpu");

labels = classifier.Layers(end).Classes;
if size(prob,1) == numel(labels) % adjust matrix depending on matlab version
    prob=prob';
end

[~, idx] = max(prob,[],2);
label = labels(idx);
frames = size(obj.image,4);
results=obj.results;
results.(classif.strid)=[];
results.(classif.strid).id=zeros(1,frames);
results.(classif.strid).prob=zeros(numel(classif.classes),size(obj.image,4));
results.(classif.strid).labels(1:frames)=categorical({''});
results.(classif.strid).labels(1:frames)=label';
results.(classif.strid).classes=classif.classes;
results.(classif.strid).prob(:,1:frames)=prob';
for i=1:numel(classif.classes)
    pix=results.(classif.strid).labels==classif.classes{i};
    results.(classif.strid).id(pix)=i;
end
obj.results = results;
%save([obj.path '/results_' obj.id '.mat'],'results');

%% measureRLS3
% results=obj.results;
    param.classifierName=classif;
    param.classes='unbud small large dead clog empty';
    param.classiftype='bud';
    param.postProcessing=1;
    param.errorDetection=0;
    %these param must be adjusted by the user, in particular if the experiment
    %is shorter than 500 frames.
    param.ArrestThreshold=175;
    param.DeathThreshold=3;
    param.ClogThreshold=1;
    param.EmptyThresholdDiscard=500; %discard roi if empty for more than this number of frames
    param.EmptyThresholdNext=100; %if encounter an empy after birth but before birth+EmptyThresholdNext, check the new RLS
    param.Frames=[];

xtraFullChannelsConservative.measureRLS_X(obj,param)

%% PixelClassi

 segch = 7; %obj.channelid(end)+1; %(usually 6?)

inputSize = net.Layers(1).InputSize;

gfp=imresize(vid(:,:,1:3,:),inputSize(1:2));
% gfp = gpuArray(gfp);
[C,score,features]= semanticseg(gfp, net,'ExecutionEnvironment',"gpu");%,'Acceleration','mex'); % this is no longer required if we extract the probabilities from the previous laye
features=imresize(features,size(tmp,1:2));

C=imresize(C,size(tmp,1:2));
classif2.outputArg={ 'threshold'  '0.9'};
classif2.outputFun = 'post';

tmpout= xtraFullChannelsConservative.post(features,classif2.classes,classif2.outputArg{:});
            xtraFullChannelsConservative.setSegmentationChannel(obj, tmpout);
% results=obj.results;

%% Colors
obj.display.rgb(4,:) = [0 1 0];
obj.display.rgb(5,:) = [1 0 0];
obj.display.rgb(6,:) = [0 0 1];
%% Full_fluo

%         obj.load();
    kMaxPix = 100;
    classiname=['full_with' num2str(kMaxPix) 'maxPixels'];

   frames = size(obj.image,4);

        cinc=1;
        for c=[4,5,6]
            for t=1:frames
                %init/reset
                obj.results.signal.full.(['from_' classiname]).meankmaxfluo(cinc,t)=NaN;
                obj.results.signal.full.(['from_' classiname]).meanfluo(cinc,t)=NaN;
                obj.results.signal.full.(['from_' classiname]).totalfluo(cinc,t)=NaN;
                %fill, reshaped used to make it line
                obj.results.signal.full.(['from_' classiname]).meankmaxfluo(cinc,t)=mean(maxk( reshape(obj.image(:,:,c,t),[],1) ,kMaxPix));
                obj.results.signal.full.(['from_' classiname]).meanfluo(cinc,t)=mean(reshape(obj.image(:,:,c,t),[],1));
                obj.results.signal.full.(['from_' classiname]).totalfluo(cinc,t)=sum(reshape(obj.image(:,:,c,t),[],1));
            end
            cinc=cinc+1;
        end
%         obj.clear;
%         obj.save('results')
%% Onemask_fluo
xtraFullChannelsConservative.compute_mother_maskedFluo([4,5,6],segch,obj)
%% Save

% obj = obj;
% results=obj.results;
% obj.log(['we did a great job'],'Processing');
% save([obj.path '/im_' obj.id 'a.mat'],'obj')
% save([obj.path '/results_' obj.id 'a.mat'], 'results')
% obj.results = results;
obj.save;
xtraFullChannelsConservative.saveResults(obj);
obj.clear;
% Current ROI.load treats a lone string as an HDF5 image-channel name.
% Reload persisted ROI data here; the pipeline adapter reloads the full ROI.
obj.load('data')

end
