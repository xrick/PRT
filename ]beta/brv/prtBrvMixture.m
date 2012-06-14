% PRTBRVMM - PRT BRV Mixture Model
%   A dirichlet density is used as the model for the mixing proportions. 
%   
%   Inherits from (prtBrv & prtBrvIVb & prtBrvVbOnline) and impliments all
%   required methods.
%
%   The construtor takes an array of prtBrvObsModel objects
%
%   obj = prtBrvMm(repmat(prtBrvMvn(2),3,1)); % A mixture with 3 2d MVNs
%
% Properties
%   mixing - prtBrvDiscrete object representing the dirichlet
%       density.
%   components - array of prtBrvObsModel components
%   nComponents - number of components in the mixture (Read only)
%
% Methods:
%   vb - Perform VB inference for the mixture
%   vbOnlineUpdate - Used within vbOnline() (Alpha release, be careful!)
%   vbNonStationaryUpdate - Performs one iteration of VB updating with
%       stabilized forgetting. (Alpha release, be careful!)


classdef prtBrvMixture < prtBrv & prtBrvVbOnline & prtBrvMembershipModel
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Properties required by prtAction
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    properties (SetAccess = private)
        name = 'Mixture Bayesian Random Variable';
        nameAbbreviation = 'BRVMix';
    end
    
    properties (SetAccess = protected)
        isSupervised = false;
        isCrossValidateValid = true;
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Methods for prtBrv
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%     
    methods
        function self = estimateParameters(self, x)
            self = conjugateUpdate(self, self, x);
        end
        
        function y = predictivePdf(self, x)
            %%%% FIXME
            % The true predictive is not finished yet. This is an
            % approximation
            
            y = conjugateVariationalAverageLogLikelihood(self, x);
        end
        
        function val = getNumDimensions(self)
            val = self.components(1).nDimensions;
        end
        
        function self = initialize(self, x)
            x = self.parseInputData(x);
            
            for iComp = 1:self.nComponents
                self.components(iComp) = self.components(iComp).initialize(x);
            end
            self.mixing = self.mixing.initialize(zeros(1,self.nComponents));
        end
        
        % Optional methods
        %------------------------------------------------------------------
        function val = plotLimits(self)
            allVal = zeros(self.nComponents, self.components(1).plotLimits);
            for s = 1:self.nComponents
                allVal(s,:) = obj.components(s).plotLimits();
            end
            val = zeros(1,size(allVal,2));
            for iDim = 1:size(allVal,2)
                if mod(iDim,2)
                    val(iDim) = min(allVal(:,iDim));
                else
                    val(iDim) = max(allVal(:,iDim));
                end
            end
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Methods for prtBrvVb
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
    methods
        function [self, training] = vbBatch(self, x)
            
            x = self.parseInputData(x);
            
            self = initialize(self,x);
            
            % Initialize
            if self.vbVerboseText
                fprintf('\n\nVB inference for a mixture model with %d components\n', self.nComponents)
                fprintf('\tInitializing VB Mixture Model\n')
            end
            
            [self, prior, training] = vbInitialize(self, x);
            
            if self.vbVerboseText
                fprintf('\tIterating VB Updates\n')
            end
            
            for iteration = 1:self.vbMaxIterations
                
                % VBM Step
                [self, training] = vbM(self, prior, x, training);
                
                % Initial VBE Step
                [self, training] = vbE(self, prior, x, training);
            
                % Calculate NFE
                [nfe, eLogLikelihood, kld] = vbNfe(self, prior, x, training);
                
                % Update training information
                training.previousNegativeFreeEnergy = training.negativeFreeEnergy;
                training.negativeFreeEnergy = nfe;
                training.iterations.negativeFreeEnergy(iteration) = nfe;
                training.iterations.eLogLikelihood(iteration) = eLogLikelihood;
                training.iterations.kld(iteration) = kld;
                training.nIterations = iteration;
                
                % Check covergence
                
                if self.vbCheckConvergence && iteration > 1
                    [converged, err] = vbIsConverged(self, prior, x, training);
                else
                    converged = false;
                    err = false;
                end
            
                % Plot
                if self.vbVerbosePlot && (mod(iteration-1,self.vbVerbosePlot) == 0)
                    vbIterationPlot(self, prior, x, training);
                    
                    if self.vbVerboseMovie
                        if isempty(self.vbVerboseMovieFrames)
                            self.vbVerboseMovieFrames = getframe(gcf);
                        else
                            self.vbVerboseMovieFrames(end+1) = getframe(gcf);
                        end
                    end
                end
                
                if converged
                    if self.vbVerboseText
                        fprintf('\tConvergence reached. Change in negative free energy below threhsold.\n')
                    end
                    break
                end
                
                if err
                    break
                end
                
            end
            if self.vbCheckConvergence && self.vbVerboseText
                fprintf('\nAll VB iterations complete.\n\n')
            end
            if self.vbCheckConvergence && ~converged && ~err && self.vbVerboseText
                fprintf('\nLearning did not complete in the allotted number of iterations.\n\n')
            end
            
            training.endTime = now;
        end
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Methods for prtBrvVbMembershipModel
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
    % We don't actualy inherit from prtBrvVbMembershipModel yet so we don't
    % actually have to implement this but we do
    methods
        function y = conjugateVariationalAverageLogLikelihood(obj,x)
            
            training = prtBrvMixtureVbTraining;
            
            [twiddle, training] = obj.vbE(obj, x, training); %#ok<ASGLU>
            y = sum(prtUtilSumExp(training.variationalLogLikelihoodBySample'));
        end
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Methods for prtBrvVbOnline
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
    methods
        function [obj, priorObj, training] = vbOnlineInitialize(obj,x)
            
            training = prtBrvMixtureVbTraining;
            
            obj = initialize(obj, x);
            
            priorObj = obj;
            
            % Intialize mixing
            obj.mixing = obj.mixing.vbOnlineInitialize([]);
            
            % Iterate through each source and update using the current memberships
            for iSource = 1:obj.nComponents
                obj.components(iSource) = obj.components(iSource).vbOnlineInitialize(x);
            end
            
        end
        
        function [obj, training] = vbOnlineUpdate(obj, priorObj, x, training, prevObj, learningRate, D)
            
            if nargin < 5 || isempty(prevObj)
                prevObj = obj;
            end
            
            if nargin < 4 || isempty(training)
                training = prtBrvMixtureVbTraining;
                training.iterations.negativeFreeEnergy = [];
                training.iterations.eLogLikelihood = [];
                training.iterations.kld = [];
                [obj, training] = obj.vbE(priorObj, x, training);
            end
            
            % Update components
            for s = 1:obj.nComponents
                obj.components(s) = obj.components(s).vbOnlineWeightedUpdate(priorObj.components(s), x, training.componentMemberships(:,s), learningRate, D, prevObj.components(s));
            end
            obj.mixing = obj.mixing.vbOnlineWeightedUpdate(priorObj.mixing, training.componentMemberships, [], learningRate, D, prevObj.mixing);
            
            training.nSamplesPerComponent = sum(training.componentMemberships,1);
            
            %[nfe, eLogLikelihood, kld, kldDetails] = vbNfe(obj, priorObj, x, training); %#ok<NASGU,ASGLU>
            %training.negativeFreeEnergy = -kld;
            
        end
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Properties and Methods for prtBrvMixture use
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods
        function self = prtBrvMixture(varargin)
            if nargin < 1
                return
            end
            
            self = constructorInputParse(self,varargin{:});
        end
        
        % This could potentially be abstracted by prtBrvVbOnlineNonStationary but
        % that does not exist yet.
        function [obj, training] = vbNonStationaryUpdate(obj, priorObj, x, training, prevObj)
            
            if nargin < 5 || isempty(prevObj)
                prevObj = obj;
            end
            
            if nargin < 4 || isempty(training)
                training = prtBrvMixtureVbTraining;
                training.startTime = now;
                training.iterations.negativeFreeEnergy = [];
                training.iterations.eLogLikelihood = [];
                training.iterations.kld = [];
                [obj, training] = obj.vbE(priorObj, x, training);
            end
            
            obj.nSamples = obj.nSamples + size(x,1);
            obj.vbOnlineT = obj.nSamples;
                        
            % Update components
            for s = 1:obj.nComponents
                cBaseDensity = prevObj.components(s).weightedConjugateUpdate(prevObj.components(s),x,training.phiMat(:,s));
                obj.components(s) = obj.components(s).vbOnlineWeightedUpdate(priorObj.components(s), x, training.phiMat(:,s), obj.vbOnlineLambda, obj.vbOnlineD, cBaseDensity);
            end
            cBaseDensity = prevObj.mixing.weightedConjugateUpdate(prevObj.mixing,training.phiMat,[]);
            obj.mixing = obj.mixing.vbOnlineWeightedUpdate(priorObj.mixing, training.phiMat, [], obj.vbOnlineLambda, obj.vbOnlineD, cBaseDensity);

        end      
    end
    
    % Some properties (some extra hidden private properties to avoid
    % property access issues  when loading and saving
    %----------------------------------------------------------------------
    properties (Dependent) 
        mixing
        components
    end
    properties (Hidden, SetAccess='private', GetAccess='private');
        internalMixing = prtBrvDiscrete;
        internalComponents = prtBrvMvn;
    end
    properties (Dependent, SetAccess='private')
        nComponents
    end
    properties (Hidden)
        plotComponentProbabilityThreshold = 0.01;
    end
    % Set and get methods for weird properties
    %----------------------------------------------------------------------
    methods
        function obj = set.components(obj,components)
            assert( isa(components,'prtBrvMembershipModel'),'components must be a prtBrvMembershipModel')
            
            obj.internalComponents = components;
        end
        
        function val = get.components(obj)
            val = obj.internalComponents;
        end
        
        function obj = set.mixing(obj,mix)
            obj.internalMixing = mix;
        end
        
        function val = get.mixing(obj)
            val = obj.internalMixing;
        end
        
        function val = get.nComponents(obj)
            val = obj.getNumComponents();
        end
        
        function val = getNumComponents(self)
            val = length(self.components);
        end
    end
    
    
    % Methods for doing VB (called by batch VB above)
    %----------------------------------------------------------------------
    methods
        function [obj, priorObj, training] = vbInitialize(obj, x)
            training = prtBrvMixtureVbTraining;
            
            priorObj = obj;
            [training.componentMemberships, priorObj.components] = collectionInitialize(obj.components, obj.components, x);
            
            training.variationalLogLikelihoodBySample = -inf(size(x,1),obj.nComponents);
        end
        
        function [obj, training] = vbE(obj, priorObj, x, training) %#ok<INUSL>
            
            % Calculate the variational Log Likelihoods of each cluster
            
            training.variationalClusterLogLikelihoods = zeros(size(x,1),obj.nComponents);
            for iSource = 1:obj.nComponents
                training.variationalClusterLogLikelihoods(:,iSource) = ...
                    obj.components(iSource).conjugateVariationalAverageLogLikelihood(x);
            end
            
            sourceVariationalLogLikelihoods = obj.mixing.expectedLogMean;
            
            training.variationalLogLikelihoodBySample = bsxfun(@plus,training.variationalClusterLogLikelihoods, sourceVariationalLogLikelihoods(:)');
            training.componentMemberships = exp(bsxfun(@minus, training.variationalLogLikelihoodBySample, prtUtilSumExp(training.variationalLogLikelihoodBySample')'));
            
        end
        
        function [obj, training] = vbM(obj, priorObj, x, training)
            
            % Iterate through each source and update using the current memberships
            for iSource = 1:obj.nComponents
                obj.components(iSource) = obj.components(iSource).weightedConjugateUpdate(priorObj.components(iSource), x, training.componentMemberships(:,iSource));
            end
    
            training.nSamplesPerComponent = sum(training.componentMemberships,1);
            
            % Updated mixing
            obj.mixing = obj.mixing.conjugateUpdate(priorObj.mixing, training.nSamplesPerComponent);
            
        end
        
        function [nfe, eLogLikelihood, kld, kldDetails] = vbNfe(obj, priorObj, x, training) %#ok<INUSL>
            
            sourceKlds = zeros(obj.nComponents,1);
            for s = 1:obj.nComponents
                sourceKlds(s) = obj.components(s).conjugateKld(priorObj.components(s));
            end
            mixingKld = obj.mixing.conjugateKld(priorObj.mixing);
            
            entropyTerm = training.componentMemberships.*log(training.componentMemberships);
            entropyTerm(isnan(entropyTerm)) = 0;
            %entropyTerm = -sum(entropyTerm(:)) + obj.mixing.expectedLogMean*sum(training.componentMemberships,1)';
            entropyTerm = -sum(entropyTerm(:));
            
            kldDetails.sources = sourceKlds(:);
            kldDetails.mixing = mixingKld;
            kldDetails.entropy = entropyTerm;
            
            kld = sum(sourceKlds) + mixingKld + entropyTerm;
            
            eLogLikelihood = sum(prtUtilSumExp(training.variationalLogLikelihoodBySample'));
            
            nfe = eLogLikelihood - kld;
        end
        
        function vbIterationPlot(obj, priorObj, x, training) %#ok<INUSL>
            
            colors = prtPlotUtilClassColors(obj.nComponents);
            
            set(gcf,'color',[1 1 1]);
            
            subplot(3,2,1)
            mixingPropPostMean = obj.mixing.posteriorMeanStruct;
            mixingPropPostMean = mixingPropPostMean.probabilities;
            
            [mixingPropPostMeanSorted, sortingInds] = sort(mixingPropPostMean,'descend');
            
            bar([mixingPropPostMeanSorted(:)'; nan(1,length(mixingPropPostMean(:)))])
            colormap(colors(sortingInds,:));
            ylim([0 1])
            xlim([0.5 1.5])
            set(gca,'XTick',[]);
            title('Source Probabilities');
            
            subplot(3,2,2)
            if ~isempty(training.iterations.negativeFreeEnergy)
                plot(training.iterations.negativeFreeEnergy,'k-')
                hold on
                plot(training.iterations.negativeFreeEnergy,'rx','markerSize',8)
                hold off
                xlim([0.5 length(training.iterations.negativeFreeEnergy)+0.5]);
            else
                plot(nan,nan)
                axis([0.5 1.5 0 1])
            end
            title('Convergence Criterion')
            xlabel('Iteration')

            subplot(3,1,2)

            componentsToPlot = mixingPropPostMean > obj.plotComponentProbabilityThreshold;
            if sum(componentsToPlot) > 0
                plotCollection(obj.components(componentsToPlot),colors(componentsToPlot,:));
            end
               
            subplot(3,1,3)
            if obj.nDimensions < 4
                [~, cY] = max(training.componentMemberships,[],2);
                allHandles = plot(prtDataSetClass(x,cY));
                
                uY = unique(cY);
                for s = 1:length(uY)
                    cColor = colors(uY(s),:);
                    set(allHandles(s),'MarkerFaceColor',cColor,'MarkerEdgeColor',prtPlotUtilLightenColors(cColor));
                end
                legend('off');
                
%                 plotLimits = [];
%                 for s = 1:obj.nComponents
%                     plotLimits(s,:) = obj.components(s).plotLimits();
%                 end
%                 plotLimits = plotLimits(componentsToPlot,:);
%                 if ~isempty(plotLimits)
%                     if obj.nDimensions == 1
%                         xlim([min(plotLimits(:,1)),max(plotLimits(:,2))]);
%                     elseif obj.nDimensions == 2
%                         axis([min(plotLimits(:,1)),max(plotLimits(:,2)),min(plotLimits(:,3)),max(plotLimits(:,4))]);
%                     end
%                 end
            
            else
                area(training.componentMemberships(:,sortingInds),'edgecolor','none')
                % colormap set above in bar.
                ylim([0 1]);
                title('Cluster Memberships');
            end
            
            drawnow;
        end
    end
    
    % Methods for prtBrvMembershipModel
    %----------------------------------------------------------------------
    methods 
        function [phiMat, priorVec] = collectionInitialize(selfVec, priorVec, x)
            if prtUtilIsSubClass(class(x),'prtDataInterfaceCategoricalTargets')
                if x.nClasses == 2
                    % This defaults to NPBMIL operation mode
                    ds = x;
                    x = ds.getObservations();
                    y = ds.getTargetsAsBinaryMatrix();
                else
                    x = x.getObservations();
                    y = [];
                end
            elseif prtUtilIsSubClass(class(x),'prtDataSetBase')
                x = x.getObservations();
            elseif isnumeric(x) || islogical(x)
                y = [];
            else
                error('prt:prtBrvMixture:parseInputData','prtBrvMixture requires a prtDataSet or a numeric 2-D matrix');
            end
            
            phiMat = zeros(size(x,1), length(selfVec));
            if ~isempty(y)
                % Special handling for NPBMIL
                nH1s = sum(y(:,2));
                randInd = prtRvUtilDiscreteRnd([1 2],[0.8 0.2],nH1s);
                phiMatH1 = zeros(nH1s, length(selfVec));
                phiMatH1(sub2ind(size(phiMatH1), (1:nH1s)',randInd)) = 1;
                
                phiMatH0 = zeros(size(x,1)-nH1s,length(selfVec));
                phiMatH0(:,1) = 1;
                
                phiMat(logical(y(:,1)),:) = phiMatH0;
                phiMat(logical(y(:,2)),:) = phiMatH1;
                
            else
                randInd = prtRvUtilDiscreteRnd([1 2],[0.5 0.5],size(x,1));
                phiMat(sub2ind(size(phiMat), (1:size(x,1))',randInd)) = 1;
            end
        end
        function self = weightedConjugateUpdate(self, prior, x, weights, training)
            
            % Iterate through each source and update using the current memberships
            for iSource = 1:self.nComponents
                self.components(iSource) = self.components(iSource).weightedConjugateUpdate(prior.components(iSource), x, weights.*training.componentMemberships(:,iSource));
            end
    
            training.nSamplesPerComponent = sum(bsxfun(@times,training.componentMemberships,weights),1);
            
            % Updated mixing
            self.mixing = self.mixing.conjugateUpdate(prior.mixing, training.nSamplesPerComponent);
            
        end
        function self = conjugateUpdate(self, prior, x) %#ok<INUSL>
            warning('prt:prtBrvMixture:conjugateUpdate','Model is not fully conjugate resorting to vb');
            self = vb(self, x);
        end
        
        function plotCollection(selfs,colors)
            
            for iComp = 1:length(selfs)
                plotCollection(selfs(iComp).components, repmat(colors(iComp,:),length(selfs(iComp).components),1));
                hold on;
                if iComp == 1
                    axesLimits = repmat(axis,length(selfs),1);
                else
                    axesLimits(iComp,:) = axis;
                end
            end
            hold off;
            axis([min(axesLimits(:,1)), max(axesLimits(:,2)), min(axesLimits(:,3)), max(axesLimits(:,4))]);
            
            
        end
        
    end
    
    methods (Hidden)
        function x = parseInputData(self,x) %#ok<MANU>
            if isnumeric(x) || islogical(x)
                return
            elseif prtUtilIsSubClass(class(x),'prtDataSetBase')
                x = x.getObservations();
            else 
                error('prt:prtBrvMixture:parseInputData','prtBrvMixture requires a prtDataSet or a numeric 2-D matrix');
            end
        end
    end    
end
        