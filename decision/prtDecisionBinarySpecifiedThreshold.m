classdef prtDecisionBinarySpecifiedThreshold < prtDecisionBinary
    % prtDecisionBinarySpecifiedThreshold Decision object for a specified
    %   threshold value
    %
    % prtDec = prtDecisionBinarySpecifiedThreshold creates a
    % prtDecisionBinarySpecifiedThreshold object, which can be used to
    % apply a decision threshold in a binary classification problem.
    %
    % A prtDecisionBinarySpecifiedThreshold has the following member:
    %
    % threshold - The specified threshold (scalar).
    %
    % prtDecision objects are intended to be used either as members of
    % prtAlgorithm or prtClass objects.
    %
    % Example 1:
    %
    % ds = prtDataGenBimodal;              % Load a data set
    % classifier = prtClassKnn;            % Create a clasifier
    % classifier = classifier.train(ds);   % Train the classifier
    % yOutClassifier = classifier.run(ds); % Run the classifier
    %
    % % Construct a prtAlgorithm object consisting of a prtClass object and
    % % a prtDecision object
    % dec = prtDecisionBinarySpecifiedThreshold;
    % dec.threshold = 2;   % Set the desired threshold (knn votes)
    % algo = prtClassKnn + dec;
    %
    % algo = algo.train(ds);        % Train the algorithm
    % yOutAlgorithm = algo.run(ds); % Run the algorithm
    %
    % % Plot and compare the results
    % subplot(2,1,1); stem(yOutClassifier.getObservations); title('KNN Output');
    % subplot(2,1,2); stem(yOutAlgorithm.getObservations); title('KNN + Decision Output');
    %
    % Example 2:
    %
    % ds = prtDataGenBimodal;              % Load a data set
    % classifier = prtClassKnn;            % Create a clasifier
    % classifier = classifier.train(ds);   % Train the classifier
    %
    % % Plot the trained classifier
    % subplot(2,1,1); plot(classifier); title('KNN');
    %
    % % Set the classifiers internealDecider to be a prtDecsion object
    % classifier.internalDecider = dec;
    %
    % classifier = classifier.train(ds); % Train the classifier
    % subplot(2,1,2); plot(classifier); title('KNN + Decision');
    %
    % See also: prtDecisionBinary, prtDecisionBinaryMinPe,
    % prtDecisionBinarySpecifiedPf, prtDecisionMap,
    % prtDecisionBinarySpecifiedPd







    
    %
    % prtDecisionBinarySpecifiedPd prt Decision action to find a threshold in a
    % binary problem to approximately acheive a specified probability of
    % detection
    %
    
    properties (SetAccess = private)
        name = 'SpecifiedThreshold'   
        nameAbbreviation = 'SpecThresh'
    end
    properties
        threshold
    end
    
    methods
        function obj = set.threshold(obj,value)
            assert(isscalar(value),'threshold parameter must be scalar');
            obj.threshold = value;
        end
    end
    methods
        function obj = prtDecisionBinarySpecifiedThreshold(varargin)
            obj = prtUtilAssignStringValuePairs(obj,varargin{:});
        end
    end
    methods (Access=protected,Hidden=true)
        
        
        function Obj = trainAction(Obj,dataSet)
            
            Obj.classList = dataSet.uniqueClasses;
        end
    end
    methods
        function threshold = getThreshold(Obj)
            threshold = Obj.threshold;
        end
    end
end
